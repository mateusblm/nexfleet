[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$sqlPath = Join-Path $projectRoot 'infra/azure/sql/bootstrap-service-roles.sql'
$mainPath = Join-Path $projectRoot 'infra/azure/main.bicep'
$platformPath = Join-Path $projectRoot 'infra/azure/modules/platform.bicep'
$workloadsPath = Join-Path $projectRoot 'infra/azure/modules/workloads.bicep'
$whatIfPath = Join-Path $PSScriptRoot 'Invoke-AzureWhatIf.ps1'
$migrationDockerfilePath = Join-Path $projectRoot 'infra/azure-database/Dockerfile'
$migrationScriptPath = Join-Path $projectRoot 'infra/azure-database/migrate.sh'

foreach ($path in @($sqlPath, $mainPath, $platformPath, $workloadsPath, $whatIfPath, $migrationDockerfilePath, $migrationScriptPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Arquivo obrigatorio ausente: $path"
    }
}

$sql = Get-Content -LiteralPath $sqlPath -Raw -Encoding UTF8
$main = Get-Content -LiteralPath $mainPath -Raw -Encoding UTF8
$platform = Get-Content -LiteralPath $platformPath -Raw -Encoding UTF8
$workloads = Get-Content -LiteralPath $workloadsPath -Raw -Encoding UTF8
$whatIf = Get-Content -LiteralPath $whatIfPath -Raw -Encoding UTF8
$migrationDockerfile = Get-Content -LiteralPath $migrationDockerfilePath -Raw -Encoding UTF8
$migrationScript = Get-Content -LiteralPath $migrationScriptPath -Raw -Encoding UTF8
$services = @('identidade', 'frota', 'operacoes', 'indicadores', 'notificacoes')

if ($sql -notmatch '(?m)^\\set ON_ERROR_STOP on$' -or $sql -notmatch '(?m)^BEGIN;$' -or $sql -notmatch '(?m)^COMMIT;$') {
    throw 'O bootstrap deve ser transacional e interromper na primeira falha.'
}

foreach ($service in $services) {
    $escaped = [regex]::Escape($service)
    if ($sql -notmatch "(?m)^REVOKE CONNECT ON DATABASE $escaped FROM PUBLIC;$") {
        throw "O banco $service ainda permite CONNECT herdado de PUBLIC."
    }
    $grantPattern = '(?m)^GRANT CONNECT, CREATE ON DATABASE {0} TO :"{0}_login";$' -f $escaped
    if ($sql -notmatch $grantPattern) {
        throw "O papel de $service nao recebeu somente CONNECT/CREATE no proprio banco."
    }
    if ($sql -notmatch "(?m)^\\gset ${escaped}_$") {
        throw "O bootstrap idempotente do papel $service nao foi encontrado."
    }
    if ($service -ne 'notificacoes' -and $workloads -notmatch "databaseCredentials\.$escaped\.login") {
        throw "O workload $service nao usa seu login exclusivo."
    }
    if ($migrationDockerfile -notmatch "migrations/$escaped") {
        throw "A imagem de migracao nao empacota os scripts de $service."
    }
    if ($migrationScript -notmatch "migrate_database $escaped $escaped") {
        throw "A imagem de migracao nao executa o banco $service."
    }
}

if ($platform -notmatch 'serviceDatabaseCredentials\.notificacoes\.login' -or
    $platform -notmatch 'serviceDatabaseCredentials\.notificacoes\.password') {
    throw 'A Function deve usar a credencial exclusiva do banco notificacoes.'
}
if ($main -notmatch '(?ms)@secure\(\)\s*@description\([^\r\n]+\)\s*param serviceDatabaseCredentials object' -or
    $platform -notmatch '(?ms)@secure\(\)\s*@description\([^\r\n]+\)\s*param serviceDatabaseCredentials object' -or
    $workloads -notmatch '(?ms)@secure\(\)\s*@description\([^\r\n]+\)\s*param databaseCredentials object') {
    throw 'As credenciais por banco devem permanecer como objetos seguros em todos os limites de modulo.'
}
if ($workloads -match 'DB_(?:USER|PASSWORD).*postgresqlAdministrator' -or
    $platform -match 'DB_(?:USER|PASSWORD).*postgresqlAdministrator') {
    throw 'O administrador PostgreSQL nao pode ser injetado em workloads.'
}
if ($sql -match "(?im)(?<!NO)SUPERUSER|(?<!NO)CREATEDB|(?<!NO)CREATEROLE|(?<!NO)BYPASSRLS") {
    throw 'Os papeis de aplicacao nao podem receber privilegios administrativos.'
}
if ($sql -match "(?im)PASSWORD\s+'[^']+'") {
    throw 'O bootstrap nao pode conter senha literal.'
}
if ($migrationDockerfile -notmatch '(?m)^USER 10001:10001$' -or
    $migrationScript -match '(?m)flyway .*-(?:password|user|url)=') {
    throw 'A imagem de migracao deve rodar sem root e nunca passar credenciais na linha de comando.'
}
if ($whatIf -notmatch "serviceDatabaseCredentials'\)" -or
    $whatIf -notmatch '\$secretValue = \[string\]\$credential\.password' -or
    $whatIf -notmatch 'Replace\(\$secretValue, ''<redacted>''\)') {
    throw 'O executor de what-if deve ocultar as cinco senhas de banco em mensagens de erro.'
}

Write-Output "Bootstrap Azure PostgreSQL valido: $($services.Count) papeis isolados e nenhum segredo literal."
