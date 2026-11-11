[CmdletBinding()]
param(
    [string]$ProfilePath,
    [string]$AdminSecretsPath
)

# Etapa 6: fluxo critico pela borda publica HTTPS (quality/azure/homolog.mjs).
# Usa a conta criada por Publish-AzureDatabaseMigration.ps1 -AdministratorEmail; a senha so
# existe como variavel de ambiente do conteiner e nao aparece em saida ou relatorio.
# Cria registros identificados por "HML" e um abastecimento, que dispara um e-mail real.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$azureInfra = Join-Path $projectRoot 'infra/azure'
if ([string]::IsNullOrWhiteSpace($ProfilePath)) { $ProfilePath = Join-Path $azureInfra 'preflight-profile.json' }
if ([string]::IsNullOrWhiteSpace($AdminSecretsPath)) {
    $AdminSecretsPath = Join-Path $projectRoot '.secrets/azure-homolog-admin.clixml'
}
if (-not (Test-Path -LiteralPath $AdminSecretsPath -PathType Leaf)) {
    throw 'Credencial do Administrador ausente. Execute Publish-AzureDatabaseMigration.ps1 -AdministratorEmail.'
}
$azureProfile = Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json

& docker info *> $null
if ($LASTEXITCODE -ne 0) { throw 'Docker indisponivel: inicie o Docker Desktop.' }

$ErrorActionPreference = 'Continue'
$apim = $null
foreach ($attempt in 1..6) {
    $apim = & az apim list -g ([string]$azureProfile.resourceGroupName) --subscription ([string]$azureProfile.subscriptionId) `
        --query '[0].name' -o tsv --only-show-errors 2>$null
    if ($LASTEXITCODE -eq 0 -and $apim) { break }
    Start-Sleep -Seconds (5 * $attempt)
}
if (-not $apim) { throw 'API Management da homologacao nao encontrado.' }

$admin = Import-Clixml -LiteralPath $AdminSecretsPath
$env:NEXFLEET_HOMOLOG_URL = "https://$apim.azure-api.net"
$env:NEXFLEET_HOMOLOG_EMAIL = [string]$admin.email
$env:NEXFLEET_HOMOLOG_PASSWORD = (New-Object System.Net.NetworkCredential('', $admin.password)).Password
$quality = Join-Path $projectRoot 'quality'
try {
    $lines = & docker run --rm -e NEXFLEET_HOMOLOG_URL -e NEXFLEET_HOMOLOG_EMAIL -e NEXFLEET_HOMOLOG_PASSWORD `
        -v "${quality}:/q:ro" node:24-bookworm node /q/azure/homolog.mjs 2>&1 | ForEach-Object { "$_" }
    $exitCode = $LASTEXITCODE
} finally {
    $env:NEXFLEET_HOMOLOG_PASSWORD = $null
    $env:NEXFLEET_HOMOLOG_EMAIL = $null
}
$ErrorActionPreference = 'Stop'

$lines | Where-Object { $_ -notmatch '^\{' } | Write-Output
$summary = $lines | Where-Object { $_ -match '^\{"aprovado"' } | Select-Object -Last 1
if ($summary) {
    $reportPath = Join-Path $azureInfra "homolog-report-$([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')).json"
    Set-Content -LiteralPath $reportPath -Value $summary -Encoding UTF8
    Write-Output "Relatorio: $reportPath"
}
if ($exitCode -ne 0) { throw 'Homologacao Azure reprovada.' }
Write-Output 'HOMOLOGACAO AZURE APROVADA.'
