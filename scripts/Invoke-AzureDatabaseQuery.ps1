[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('identidade', 'frota', 'operacoes', 'indicadores', 'notificacoes')]
    [string]$Database,
    [Parameter(Mandatory)]
    [string]$Sql,
    [string]$ProfilePath,
    # Libera INSERT/UPDATE/DELETE. Sem esta chave a sessao e somente leitura.
    [switch]$PermitirEscrita
)

# Consulta no PostgreSQL privado da homologacao Azure. Por padrao, SOMENTE LEITURA.
# O servidor nao tem acesso publico: a consulta roda dentro da VNet, como execucao do job
# job-nexfleet-db-verify com comando sobrescrito, usando o papel do proprio banco (nunca o
# administrador). Sem -PermitirEscrita a sessao abre com default_transaction_read_only=on,
# entao INSERT/UPDATE/DELETE/DDL falham. Com -PermitirEscrita o script pede confirmacao.
# O resultado volta pelo Log Analytics (1 a 3 minutos de espera).
# Exemplos:
#   ./scripts/Invoke-AzureDatabaseQuery.ps1 -Database frota -Sql "SELECT placa, status FROM frota.veiculo"
#   ./scripts/Invoke-AzureDatabaseQuery.ps1 -Database identidade -PermitirEscrita `
#       -Sql "DELETE FROM identidade.usuario WHERE email = 'x@example.com' RETURNING email"

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$sessionOptions = '-c default_transaction_read_only=on -c statement_timeout=30000'
if ($PermitirEscrita) {
    Write-Host "ATENCAO: este comando ALTERA o banco '$Database' da Azure e nao pode ser desfeito:" -ForegroundColor Yellow
    Write-Host "  $Sql" -ForegroundColor Yellow
    if ((Read-Host 'Digite CONFIRMAR para executar') -cne 'CONFIRMAR') { throw 'Operacao cancelada.' }
    $sessionOptions = '-c statement_timeout=30000'
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$azureInfra = Join-Path $projectRoot 'infra/azure'
if ([string]::IsNullOrWhiteSpace($ProfilePath)) { $ProfilePath = Join-Path $azureInfra 'preflight-profile.json' }
$azureProfile = Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
$subscriptionId = [string]$azureProfile.subscriptionId
$resourceGroup = [string]$azureProfile.resourceGroupName
$version = (Get-Content -LiteralPath (Join-Path $projectRoot 'VERSION') -Raw -Encoding UTF8).Trim()
$arm = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers"
$jobUrl = "$arm/Microsoft.App/jobs/job-nexfleet-db-verify"

function Invoke-AzRetry([string[]]$Arguments, [int]$Attempts = 8) {
    $ErrorActionPreference = 'Continue'
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        $output = & az @Arguments --subscription $subscriptionId --only-show-errors -o json 2>$null
        if ($LASTEXITCODE -eq 0) {
            if ($output) { return (($output -join "`n") | ConvertFrom-Json) }
            return $null
        }
        Start-Sleep -Seconds (5 * $attempt)
    }
    throw "Falha persistente: az $($Arguments[0..1] -join ' ') ..."
}

$server = @(Invoke-AzRetry @('postgres', 'flexible-server', 'list', '-g', $resourceGroup) |
    Where-Object { $_.name -notlike 'psql-nexfleet-cq10-*' })[0]
$registry = @(Invoke-AzRetry @('acr', 'list', '-g', $resourceGroup))[0]
$workspace = @(Invoke-AzRetry @('monitor', 'log-analytics', 'workspace', 'list', '-g', $resourceGroup))[0].customerId

# Marcador unico para separar o resultado desta execucao no Log Analytics.
$marker = "RESULTADO-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$upper = $Database.ToUpperInvariant()
$script = @"
set -eu
export PGHOST="`$DB_HOST" PGSSLMODE=require PGDATABASE=$Database
export PGUSER="`$${upper}_DB_USER" PGPASSWORD="`$${upper}_DB_PASSWORD"
export PGOPTIONS='$sessionOptions'
printf '%s\n' "`$NX_SQL" | psql --no-password -v ON_ERROR_STOP=1 -P pager=off -P footer=on 2>&1 | sed 's/^/$marker | /'
echo '$marker | FIM'
"@

$body = @{ containers = @(@{
    name = 'database'
    image = "$($registry.loginServer)/azure-database:$version"
    command = @('/bin/sh', '-c', $script)
    env = @(
        @{ name = 'DB_HOST'; value = [string]$server.fullyQualifiedDomainName },
        @{ name = "${upper}_DB_USER"; value = "nexfleet_$Database" },
        @{ name = "${upper}_DB_PASSWORD"; secretRef = "$Database-db-password" },
        @{ name = 'NX_SQL'; value = $Sql }
    )
    resources = @{ cpu = 0.5; memory = '1Gi' }
}) } | ConvertTo-Json -Depth 8
$bodyFile = Join-Path ([IO.Path]::GetTempPath()) "nexfleet-query-$([guid]::NewGuid().ToString('N')).json"
try {
    Set-Content -LiteralPath $bodyFile -Value $body -Encoding UTF8
    $started = Invoke-AzRetry @('rest', '--method', 'post', '--url', "$jobUrl/start?api-version=2024-03-01", '--body', "@$bodyFile")
} finally { Remove-Item -LiteralPath $bodyFile -Force -ErrorAction SilentlyContinue }
$execution = [string]$started.name
Write-Host "Consulta enviada ($execution). Aguardando a execucao dentro da VNet..."

$deadline = (Get-Date).AddMinutes(10)
$status = ''
while ((Get-Date) -lt $deadline -and $status -notin @('Succeeded', 'Failed', 'Stopped')) {
    Start-Sleep -Seconds 15
    try {
        $exec = Invoke-AzRetry @('rest', '--method', 'get', '--url', "$jobUrl/executions/${execution}?api-version=2024-03-01") 2
        if ($exec.properties.PSObject.Properties['status']) { $status = [string]$exec.properties.status }
    } catch { continue }
}
Write-Host "Execucao: $status. Lendo o resultado no Log Analytics (pode levar alguns minutos)..."

$kql = "ContainerAppConsoleLogs_CL | where ContainerGroupName_s startswith '$execution' | where Log_s startswith '$marker' | project TimeGenerated, Log_s | order by TimeGenerated asc"
$queryFile = Join-Path ([IO.Path]::GetTempPath()) "nexfleet-query-kql-$([guid]::NewGuid().ToString('N')).json"
Set-Content -LiteralPath $queryFile -Value (@{ query = $kql } | ConvertTo-Json -Compress) -Encoding ASCII
try {
    for ($attempt = 1; $attempt -le 16; $attempt++) {
        $result = Invoke-AzRetry @('rest', '--method', 'post', '--url', "https://api.loganalytics.io/v1/workspaces/$workspace/query",
            '--resource', 'https://api.loganalytics.io', '--body', "@$queryFile")
        $lines = @($result.tables[0].rows | ForEach-Object { ([string]$_[1]).Substring($marker.Length + 3) })
        if ($lines -contains 'FIM') {
            # Linhas com o mesmo instante podem chegar fora de ordem; o psql numera o rodape.
            $lines | Where-Object { $_ -ne 'FIM' } | Write-Output
            # O pipeline psql | sed devolve o codigo do sed; o erro real aparece como "ERROR:".
            if ($status -ne 'Succeeded' -or ($lines -match '^(ERROR|FATAL):')) {
                throw 'A consulta falhou; veja a mensagem do PostgreSQL acima.'
            }
            return
        }
        Start-Sleep -Seconds 20
    }
} finally { Remove-Item -LiteralPath $queryFile -Force -ErrorAction SilentlyContinue }
throw "O resultado da execucao $execution nao chegou ao Log Analytics a tempo."
