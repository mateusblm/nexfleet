param(
    [string]$PostgresImage = 'postgres:18-alpine'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$localJava = Get-ChildItem (Join-Path $projectRoot '.tools/temurin-jdk-21') `
    -Filter java.exe -File -Recurse -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not (Get-Command java.exe -ErrorAction SilentlyContinue) -and $localJava) {
    $env:JAVA_HOME = Split-Path -Parent (Split-Path -Parent $localJava.FullName)
    $env:Path = "$env:JAVA_HOME\bin;$env:Path"
}
if (-not (Get-Command java.exe -ErrorAction SilentlyContinue)) {
    throw 'JDK 21 não encontrado. Execute primeiro scripts/Install-Dependencies.ps1.'
}
$javaVersion = (& java --version | Select-Object -First 1).ToString()
if ($javaVersion -notmatch '(?:version "|openjdk )21(?:\.|\")') {
    throw "O teste integrado exige JDK 21. Versão encontrada: $javaVersion"
}
$containerName = 'nexfleet-cq03-cq04-' + [guid]::NewGuid().ToString('N').Substring(0, 12)
$database = 'operacoes'
$databaseUser = 'nexfleet_integracao'
$databasePassword = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
$environmentNames = @(
    'NEXFLEET_INTEGRATION_DB_URL',
    'NEXFLEET_INTEGRATION_DB_USER',
    'NEXFLEET_INTEGRATION_DB_PASSWORD'
)
$previousEnvironment = @{}
foreach ($name in $environmentNames) {
    $previousEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, 'Process')
}

function Invoke-DockerChecked {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    & docker @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Falha no Docker: docker $($Arguments -join ' ')"
    }
}

try {
    & docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker Desktop não está disponível. Inicie-o e tente novamente.'
    }

    Write-Output 'Criando PostgreSQL temporário para CQ03 e CQ04...'
    Invoke-DockerChecked run --detach --name $containerName `
        --publish '127.0.0.1::5432' `
        --env "POSTGRES_DB=$database" `
        --env "POSTGRES_USER=$databaseUser" `
        --env "POSTGRES_PASSWORD=$databasePassword" `
        $PostgresImage | Out-Null

    $ready = $false
    for ($attempt = 1; $attempt -le 60; $attempt++) {
        & docker exec $containerName pg_isready -U $databaseUser -d $database *> $null
        if ($LASTEXITCODE -eq 0) {
            $ready = $true
            break
        }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) {
        throw 'O PostgreSQL temporário não ficou pronto dentro de 60 segundos.'
    }

    $portMapping = (& docker port $containerName '5432/tcp' | Select-Object -First 1).ToString()
    $portMatch = [regex]::Match($portMapping, '^127\.0\.0\.1:(\d+)$')
    if (-not $portMatch.Success) {
        throw "Não foi possível identificar a porta local do PostgreSQL temporário: $portMapping"
    }

    $env:NEXFLEET_INTEGRATION_DB_URL = "jdbc:postgresql://127.0.0.1:$($portMatch.Groups[1].Value)/$database"
    $env:NEXFLEET_INTEGRATION_DB_USER = $databaseUser
    $env:NEXFLEET_INTEGRATION_DB_PASSWORD = $databasePassword

    $isWindows = $PSVersionTable.PSEdition -eq 'Desktop' -or $env:OS -eq 'Windows_NT'
    $mavenWrapper = if ($isWindows) {
        Join-Path $projectRoot 'services/mvnw.cmd'
    } else {
        Join-Path $projectRoot 'services/mvnw'
    }
    $mavenArgs = @(
        '--batch-mode',
        '--no-transfer-progress',
        '-Dmaven.compiler.fork=true',
        '-Dtest=JdbcAbastecimentosIT',
        'test'
    )
    $localMavenRepository = Join-Path $projectRoot '.cache/maven-repository'
    if (Test-Path -LiteralPath $localMavenRepository) {
        $env:MAVEN_USER_HOME = Join-Path $projectRoot '.cache/maven-home'
        $mavenArgs = @("-Dmaven.repo.local=$localMavenRepository") + $mavenArgs
    }

    Push-Location (Join-Path $projectRoot 'services/operacoes')
    try {
        & $mavenWrapper @mavenArgs
        if ($LASTEXITCODE -ne 0) {
            throw 'Falha nos testes integrados CQ03/CQ04.'
        }
    } finally {
        Pop-Location
    }

    Write-Output 'CQ03 e CQ04 aprovados em PostgreSQL temporário; nenhum banco ativo foi alterado.'
} finally {
    foreach ($name in $environmentNames) {
        $previous = $previousEnvironment[$name]
        if ($null -eq $previous) {
            Remove-Item -Path "Env:$name" -ErrorAction SilentlyContinue
        } else {
            [Environment]::SetEnvironmentVariable($name, $previous, 'Process')
        }
    }
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        & docker rm --force $containerName *> $null
    }
}
