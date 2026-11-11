param(
    [string]$PostgresImage = 'postgres:18-alpine',
    [string]$JavaRuntimeImage = 'eclipse-temurin:21-jre-jammy'
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

$suffix = [guid]::NewGuid().ToString('N').Substring(0, 12)
$networkName = "nexfleet-cq07-$suffix"
$databaseContainer = "nexfleet-cq07-db-$suffix"
$serviceContainer = "nexfleet-cq07-frota-$suffix"
$database = 'frota'
$databaseUser = 'nexfleet_cq07'
$databasePassword = 'cq07-db-secret-' + [guid]::NewGuid().ToString('N')
$bearerSecret = 'cq07-bearer-secret-' + [guid]::NewGuid().ToString('N')
$correlationId = [guid]::NewGuid().ToString()
$script:httpClient = $null

function Invoke-DockerChecked {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    & docker @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Falha no Docker: docker $($Arguments -join ' ')"
    }
}

function Invoke-HttpProbe {
    param(
        [string]$Url,
        [string]$Correlation,
        [string]$Bearer
    )
    $request = [System.Net.Http.HttpRequestMessage]::new(
        [System.Net.Http.HttpMethod]::Get,
        $Url)
    $response = $null
    try {
        if ($Correlation) {
            [void]$request.Headers.TryAddWithoutValidation('X-Correlation-ID', $Correlation)
        }
        if ($Bearer) {
            [void]$request.Headers.TryAddWithoutValidation('Authorization', "Bearer $Bearer")
        }
        $response = $script:httpClient.SendAsync($request).GetAwaiter().GetResult()
        $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $returnedCorrelation = $null
        if ($response.Headers.Contains('X-Correlation-ID')) {
            $returnedCorrelation = ($response.Headers.GetValues('X-Correlation-ID') | Select-Object -First 1)
        }
        return [pscustomobject]@{
            Status = [int]$response.StatusCode
            Content = $content
            Correlation = $returnedCorrelation
        }
    } finally {
        if ($response) { $response.Dispose() }
        $request.Dispose()
    }
}

function Wait-ForHealthStatus {
    param(
        [string]$Url,
        [int]$HttpStatus,
        [string]$HealthStatus,
        [int]$Attempts = 60
    )
    $lastResult = 'sem resposta'
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            $probe = Invoke-HttpProbe -Url $Url
            $body = $probe.Content | ConvertFrom-Json
            $lastResult = "HTTP $($probe.Status), status $($body.status)"
            if ($probe.Status -eq $HttpStatus -and $body.status -eq $HealthStatus) {
                return $probe
            }
        } catch {
            $lastResult = $_.Exception.Message
        }
        Start-Sleep -Seconds 2
    }
    throw "Estado esperado não observado em ${Url}: $lastResult"
}

try {
    & docker info *> $null
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker Desktop não está disponível. Inicie-o e tente novamente.'
    }

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
        '-DskipTests',
        'package'
    )
    $localMavenRepository = Join-Path $projectRoot '.cache/maven-repository'
    if (Test-Path -LiteralPath $localMavenRepository) {
        $env:MAVEN_USER_HOME = Join-Path $projectRoot '.cache/maven-home'
        $mavenArgs = @("-Dmaven.repo.local=$localMavenRepository") + $mavenArgs
    }

    Write-Output 'Preparando o artefato do serviço Frota...'
    Push-Location (Join-Path $projectRoot 'services/frota')
    try {
        & $mavenWrapper @mavenArgs
        if ($LASTEXITCODE -ne 0) {
            throw 'Falha ao empacotar o serviço Frota para CQ07.'
        }
    } finally {
        Pop-Location
    }

    $jarPath = (Resolve-Path (Join-Path $projectRoot 'services/frota/target/app.jar')).Path
    Add-Type -AssemblyName System.Net.Http
    $handler = [System.Net.Http.HttpClientHandler]::new()
    $script:httpClient = [System.Net.Http.HttpClient]::new($handler)
    $script:httpClient.Timeout = [TimeSpan]::FromSeconds(5)

    Write-Output 'Criando rede, banco e serviço temporários para CQ07...'
    Invoke-DockerChecked network create $networkName | Out-Null
    Invoke-DockerChecked run --detach --name $databaseContainer `
        --network $networkName `
        --network-alias frota-db `
        --env "POSTGRES_DB=$database" `
        --env "POSTGRES_USER=$databaseUser" `
        --env "POSTGRES_PASSWORD=$databasePassword" `
        $PostgresImage | Out-Null

    $databaseReady = $false
    for ($attempt = 1; $attempt -le 60; $attempt++) {
        & docker exec $databaseContainer pg_isready -U $databaseUser -d $database *> $null
        if ($LASTEXITCODE -eq 0) {
            $databaseReady = $true
            break
        }
        Start-Sleep -Seconds 1
    }
    if (-not $databaseReady) {
        throw 'O PostgreSQL temporário não ficou pronto dentro de 60 segundos.'
    }

    $mount = "type=bind,source=$jarPath,target=/app/app.jar,readonly"
    Invoke-DockerChecked run --detach --name $serviceContainer `
        --network $networkName `
        --publish '127.0.0.1::8080' `
        --env 'DB_URL=jdbc:postgresql://frota-db:5432/frota' `
        --env "DB_USER=$databaseUser" `
        --env "DB_PASSWORD=$databasePassword" `
        --mount $mount `
        $JavaRuntimeImage `
        java '-XX:MaxRAMPercentage=65.0' -jar /app/app.jar | Out-Null

    $portMapping = (& docker port $serviceContainer '8080/tcp' | Select-Object -First 1).ToString()
    $portMatch = [regex]::Match($portMapping, '^127\.0\.0\.1:(\d+)$')
    if (-not $portMatch.Success) {
        throw "Não foi possível identificar a porta do serviço temporário: $portMapping"
    }
    $baseUrl = "http://127.0.0.1:$($portMatch.Groups[1].Value)"

    Write-Output 'Confirmando readiness saudável com o banco disponível...'
    [void](Wait-ForHealthStatus `
        -Url "$baseUrl/actuator/health/readiness" `
        -HttpStatus 200 `
        -HealthStatus 'UP')

    Write-Output 'Interrompendo somente o banco temporário...'
    Invoke-DockerChecked stop --time 5 $databaseContainer | Out-Null

    Write-Output 'Confirmando readiness não saudável...'
    [void](Wait-ForHealthStatus `
        -Url "$baseUrl/actuator/health/readiness" `
        -HttpStatus 503 `
        -HealthStatus 'DOWN')

    $info = Invoke-HttpProbe `
        -Url "$baseUrl/api/v1/frota/info" `
        -Correlation $correlationId `
        -Bearer $bearerSecret
    $infoBody = $info.Content | ConvertFrom-Json
    if ($info.Status -ne 503 -or $infoBody.status -ne 'DOWN') {
        throw "A API técnica não refletiu a indisponibilidade: HTTP $($info.Status), status $($infoBody.status)."
    }
    if ($info.Correlation -ne $correlationId) {
        throw "A resposta não preservou X-Correlation-ID. Esperado: $correlationId; recebido: $($info.Correlation)."
    }

    $logs = ''
    for ($attempt = 1; $attempt -le 20; $attempt++) {
        $logs = (& docker logs $serviceContainer 2>&1 | Out-String)
        if ($logs.Contains("correlationId=$correlationId") -and
            $logs.Contains('path=/api/v1/frota/info status=503')) {
            break
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not $logs.Contains("correlationId=$correlationId")) {
        throw 'O log não contém o correlationId usado durante a falha.'
    }
    if (-not $logs.Contains('path=/api/v1/frota/info status=503')) {
        throw 'O log não contém o resultado 503 da consulta durante a falha.'
    }
    if ($logs.Contains($databasePassword)) {
        throw 'O log expôs a senha sentinela do banco.'
    }
    if ($logs.Contains($bearerSecret)) {
        throw 'O log expôs o token Bearer sentinela.'
    }

    Write-Output 'CQ07 aprovado: readiness DOWN/503 e log correlacionado sem senha ou token.'
} finally {
    if ($script:httpClient) { $script:httpClient.Dispose() }
    if (Get-Command docker -ErrorAction SilentlyContinue) {
        & docker rm --force $serviceContainer $databaseContainer *> $null
        & docker network rm $networkName *> $null
    }
}
