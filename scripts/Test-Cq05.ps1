param(
    [string]$PostgresImage = 'postgres:18-alpine'
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$localJava = Get-ChildItem (Join-Path $projectRoot '.tools/temurin-jdk-21') `
    -Filter java.exe -File -Recurse -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not (Get-Command java -ErrorAction SilentlyContinue) -and $localJava) {
    $env:JAVA_HOME = Split-Path -Parent (Split-Path -Parent $localJava.FullName)
    $env:Path = "$env:JAVA_HOME\bin;$env:Path"
}
if (-not (Get-Command java -ErrorAction SilentlyContinue)) {
    throw 'JDK 21 não encontrado. Execute primeiro scripts/Install-Dependencies.ps1.'
}
$javaVersion = (& java --version | Select-Object -First 1).ToString()
if ($javaVersion -notmatch '(?:version "|openjdk )21(?:\.|\")') {
    throw "O teste integrado exige JDK 21. Versão encontrada: $javaVersion"
}

$suffix = [guid]::NewGuid().ToString('N').Substring(0, 12)
$frotaContainer = "nexfleet-cq05-frota-$suffix"
$operacoesContainer = "nexfleet-cq05-operacoes-$suffix"
$databaseUser = 'nexfleet_integracao'
$databasePassword = [guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N')
$environmentNames = @(
    'NEXFLEET_CQ05_FROTA_DB_URL',
    'NEXFLEET_CQ05_FROTA_DB_USER',
    'NEXFLEET_CQ05_FROTA_DB_PASSWORD',
    'NEXFLEET_CQ05_OPERACOES_DB_URL',
    'NEXFLEET_CQ05_OPERACOES_DB_USER',
    'NEXFLEET_CQ05_OPERACOES_DB_PASSWORD',
    'NEXFLEET_CQ05_VEICULO_ID',
    'NEXFLEET_CQ05_MOTORISTA_ID',
    'NEXFLEET_CQ05_AUTOR_ID'
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

function Start-TemporaryPostgres {
    param([string]$Container, [string]$Database)
    Invoke-DockerChecked run --detach --name $Container `
        --publish '127.0.0.1::5432' `
        --env "POSTGRES_DB=$Database" `
        --env "POSTGRES_USER=$databaseUser" `
        --env "POSTGRES_PASSWORD=$databasePassword" `
        $PostgresImage | Out-Null

    $ready = $false
    for ($attempt = 1; $attempt -le 60; $attempt++) {
        & docker exec $Container pg_isready -U $databaseUser -d $Database *> $null
        if ($LASTEXITCODE -eq 0) {
            $ready = $true
            break
        }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) {
        throw "O PostgreSQL temporário $Container não ficou pronto dentro de 60 segundos."
    }

    $portMapping = (& docker port $Container '5432/tcp' | Select-Object -First 1).ToString()
    $portMatch = [regex]::Match($portMapping, '^127\.0\.0\.1:(\d+)$')
    if (-not $portMatch.Success) {
        throw "Não foi possível identificar a porta local de ${Container}: $portMapping"
    }
    return "jdbc:postgresql://127.0.0.1:$($portMatch.Groups[1].Value)/$Database"
}

function Invoke-MavenPhase {
    param([string]$Module, [string]$Selector, [string]$Description)
    Write-Output $Description
    Push-Location (Join-Path $projectRoot "services/$Module")
    try {
        & $script:mavenWrapper @script:mavenBaseArgs "-Dtest=$Selector" test
        if ($LASTEXITCODE -ne 0) {
            throw "Falha na etapa CQ05: $Description"
        }
    } finally {
        Pop-Location
    }
}

try {
    & docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker Desktop não está disponível. Inicie-o e tente novamente.'
    }

    Write-Output 'Criando bancos PostgreSQL temporários e separados para Frota e Operações...'
    $env:NEXFLEET_CQ05_FROTA_DB_URL = Start-TemporaryPostgres $frotaContainer 'frota'
    $env:NEXFLEET_CQ05_OPERACOES_DB_URL = Start-TemporaryPostgres $operacoesContainer 'operacoes'
    $env:NEXFLEET_CQ05_FROTA_DB_USER = $databaseUser
    $env:NEXFLEET_CQ05_FROTA_DB_PASSWORD = $databasePassword
    $env:NEXFLEET_CQ05_OPERACOES_DB_USER = $databaseUser
    $env:NEXFLEET_CQ05_OPERACOES_DB_PASSWORD = $databasePassword
    $env:NEXFLEET_CQ05_VEICULO_ID = [guid]::NewGuid().ToString()
    $env:NEXFLEET_CQ05_MOTORISTA_ID = [guid]::NewGuid().ToString()
    $env:NEXFLEET_CQ05_AUTOR_ID = [guid]::NewGuid().ToString()

    $isWindows = $PSVersionTable.PSEdition -eq 'Desktop' -or $env:OS -eq 'Windows_NT'
    $script:mavenWrapper = if ($isWindows) {
        Join-Path $projectRoot 'services/mvnw.cmd'
    } else {
        Join-Path $projectRoot 'services/mvnw'
    }
    $script:mavenBaseArgs = @(
        '--batch-mode',
        '--no-transfer-progress',
        '-Dmaven.compiler.fork=true'
    )
    $localMavenRepository = Join-Path $projectRoot '.cache/maven-repository'
    if (Test-Path -LiteralPath $localMavenRepository) {
        $env:MAVEN_USER_HOME = Join-Path $projectRoot '.cache/maven-home'
        $script:mavenBaseArgs = @("-Dmaven.repo.local=$localMavenRepository") + $script:mavenBaseArgs
    }

    Invoke-MavenPhase 'frota' `
        'Cq05HistoricoVeiculoIT#cq05CriarVeiculoAtivo' `
        '1/4 - Criando o veículo ativo no serviço Frota...'
    Invoke-MavenPhase 'operacoes' `
        'Cq05HistoricoVeiculoIT#cq05RegistrarOperacaoAntesDaInativacao' `
        '2/4 - Registrando o abastecimento no serviço Operações...'
    Invoke-MavenPhase 'frota' `
        'Cq05HistoricoVeiculoIT#cq05InativarVeiculoSemExcluirCadastro' `
        '3/4 - Inativando o veículo sem excluir seu cadastro...'
    Invoke-MavenPhase 'operacoes' `
        'Cq05HistoricoVeiculoIT#cq05ConsultarHistoricoDepoisDaInativacaoMantemDataEResponsavel' `
        '4/4 - Consultando o histórico com data e motorista responsável...'

    Write-Output 'CQ05 aprovado em bancos temporários: o histórico permaneceu consultável após a inativação.'
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
        & docker rm --force $frotaContainer $operacoesContainer *> $null
    }
}
