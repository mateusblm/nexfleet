[CmdletBinding()]
param(
    [string]$OutputDirectory
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$envPath = Join-Path $projectRoot '.env.sprint0'
if (-not (Test-Path -LiteralPath $envPath)) {
    throw 'Execute ./scripts/Initialize-Local.ps1 antes de criar backups.'
}
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker nao foi encontrado.'
}

if ([String]::IsNullOrWhiteSpace($OutputDirectory)) {
    $timestamp = [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $OutputDirectory = Join-Path $projectRoot "backups/$timestamp"
}
$outputPath = [IO.Path]::GetFullPath($OutputDirectory)
if (-not (Test-Path -LiteralPath $outputPath)) {
    [void](New-Item -ItemType Directory -Path $outputPath -Force)
}
if ((Get-ChildItem -LiteralPath $outputPath -Force | Measure-Object).Count -gt 0) {
    throw "O diretorio de backup deve estar vazio: $outputPath"
}

$composeArgs = @(
    'compose', '--env-file', $envPath,
    '-f', (Join-Path $projectRoot 'compose.sprint0.yaml'),
    '-f', (Join-Path $projectRoot 'compose.jwt-rsa.yaml')
)
$databases = @(
    [ordered]@{ service = 'identidade-db'; database = 'identidade'; user = 'identidade'; schema = 'identidade' },
    [ordered]@{ service = 'frota-db'; database = 'frota'; user = 'frota'; schema = 'frota' },
    [ordered]@{ service = 'operacoes-db'; database = 'operacoes'; user = 'operacoes'; schema = 'operacoes' },
    [ordered]@{ service = 'indicadores-db'; database = 'indicadores'; user = 'indicadores'; schema = 'indicadores' },
    [ordered]@{ service = 'notificacoes-db'; database = 'notificacoes'; user = 'notificacoes'; schema = 'notificacoes' }
)
$manifest = [ordered]@{
    formatVersion = 1
    createdUtc = [DateTime]::UtcNow.ToString('o')
    source = 'NexFleet Docker Compose local'
    rpoTargetHours = 24
    databases = @()
}

foreach ($database in $databases) {
    $serviceName = [string]$database.service
    $containerOutput = & docker @composeArgs ps -q $serviceName
    $container = ([string]($containerOutput | Select-Object -First 1)).Trim()
    if ($LASTEXITCODE -ne 0 -or [String]::IsNullOrWhiteSpace($container)) {
        throw "O banco $($database.service) nao esta em execucao. Suba o backend antes do backup."
    }

    $fileName = "$($database.database).dump"
    $hostFile = Join-Path $outputPath $fileName
    $containerFile = "/tmp/nexfleet-cq10-$([guid]::NewGuid().ToString('N')).dump"
    try {
        & docker exec $container pg_dump `
            "--username=$($database.user)" `
            "--dbname=$($database.database)" `
            --format=custom --compress=9 --no-owner --no-privileges `
            "--file=$containerFile"
        if ($LASTEXITCODE -ne 0) { throw "pg_dump falhou para $($database.database)." }

        & docker cp "${container}:$containerFile" $hostFile
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $hostFile)) {
            throw "Nao foi possivel copiar o backup de $($database.database)."
        }
    } finally {
        & docker exec $container rm -f $containerFile 2>$null
    }

    $tableSql = "SELECT schemaname || '|' || tablename FROM pg_tables WHERE schemaname = '$($database.schema)' ORDER BY tablename;"
    $tableLines = @(& docker exec $container psql `
        "--username=$($database.user)" "--dbname=$($database.database)" `
        --no-psqlrc --tuples-only --no-align --set ON_ERROR_STOP=1 `
        --command $tableSql)
    if ($LASTEXITCODE -ne 0) { throw "Falha ao inventariar $($database.database)." }

    $tables = @()
    foreach ($line in $tableLines) {
        $trimmed = ([string]$line).Trim()
        if ([String]::IsNullOrWhiteSpace($trimmed)) { continue }
        $parts = $trimmed.Split('|', 2)
        if ($parts.Count -ne 2 -or $parts[0] -notmatch '^[a-z0-9_]+$' -or $parts[1] -notmatch '^[a-z0-9_]+$') {
            throw "Identificador inesperado no banco $($database.database)."
        }
        $countSql = 'SELECT COUNT(*) FROM "{0}"."{1}";' -f $parts[0], $parts[1]
        $countOutput = & docker exec $container psql `
            "--username=$($database.user)" "--dbname=$($database.database)" `
            --no-psqlrc --tuples-only --no-align --set ON_ERROR_STOP=1 `
            --command $countSql
        if ($LASTEXITCODE -ne 0) { throw "Falha ao contar $trimmed." }
        $tables += [ordered]@{ name = "$($parts[0]).$($parts[1])"; rows = [long](([string]$countOutput).Trim()) }
    }

    $file = Get-Item -LiteralPath $hostFile
    $manifest.databases += [ordered]@{
        service = $database.service
        database = $database.database
        user = $database.user
        schema = $database.schema
        file = $fileName
        bytes = $file.Length
        sha256 = (Get-FileHash -LiteralPath $hostFile -Algorithm SHA256).Hash
        tables = $tables
    }
    Write-Output "Backup criado: $($database.database) ($($tables.Count) tabelas)."
}

$manifestPath = Join-Path $outputPath 'manifest.json'
$json = $manifest | ConvertTo-Json -Depth 10
[IO.File]::WriteAllText($manifestPath, $json, [Text.UTF8Encoding]::new($false))
Write-Output "Backups concluidos em: $outputPath"
Write-Output 'Proteja esse diretorio: os arquivos contem dados do sistema e nao devem ir para o Git.'
