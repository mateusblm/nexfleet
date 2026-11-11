[CmdletBinding()]
param(
    [string]$ProfilePath,
    [switch]$SkipBuild,
    [switch]$Authorize
)

# Publica shell e microfrontends no Azure Static Web Apps (ADR 0037).
# - build com VITE_API_BASE_URL apontando para o APIM HTTPS (Build-AzureFrontend.ps1);
# - envio pela SWA CLI fixada em 2.0.10 dentro de um conteiner Node completo: o binario
#   StaticSitesClient precisa de bibliotecas nativas ausentes na imagem slim;
# - o token de implantacao vai como argumento direto (sem sh -c) e nunca e gravado em disco.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $Authorize) { throw 'Execucao bloqueada. Use -Authorize depois dos workloads Azure publicados.' }

$projectRoot = Split-Path -Parent $PSScriptRoot
$azureInfra = Join-Path $projectRoot 'infra/azure'
if ([string]::IsNullOrWhiteSpace($ProfilePath)) { $ProfilePath = Join-Path $azureInfra 'preflight-profile.json' }
$azureProfile = Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
$subscriptionId = [string]$azureProfile.subscriptionId
$resourceGroup = [string]$azureProfile.resourceGroupName
$output = Join-Path $projectRoot 'output/azure-web'

& docker info *> $null
if ($LASTEXITCODE -ne 0) { throw 'Docker indisponivel: inicie o Docker Desktop (o envio usa um conteiner Node).' }

function Invoke-AzText([string[]]$Arguments) {
    $ErrorActionPreference = 'Continue'
    foreach ($attempt in 1..6) {
        $value = & az @Arguments --subscription $subscriptionId --only-show-errors -o tsv 2>$null
        if ($LASTEXITCODE -eq 0 -and $value) { return [string]$value }
        Start-Sleep -Seconds (5 * $attempt)
    }
    throw "Falha persistente: az $($Arguments[0..1] -join ' ') ..."
}

$apim = Invoke-AzText @('apim', 'list', '-g', $resourceGroup, '--query', '[0].name')
$apiBaseUrl = "https://$apim.azure-api.net"
$site = Invoke-AzText @('staticwebapp', 'list', '-g', $resourceGroup, '--query', '[0].name')
$hostname = Invoke-AzText @('staticwebapp', 'show', '-g', $resourceGroup, '-n', $site, '--query', 'defaultHostname')

if (-not $SkipBuild) {
    if (-not (Get-Command npm.cmd -ErrorAction SilentlyContinue)) {
        $localNode = Get-ChildItem (Join-Path $projectRoot '.tools') -Directory -Filter 'node-v*-win-x64' -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($localNode) { $env:Path = "$($localNode.FullName);$env:Path" }
    }
    & (Join-Path $PSScriptRoot 'Build-AzureFrontend.ps1') -ApiBaseUrl $apiBaseUrl
}
if (-not (Test-Path -LiteralPath (Join-Path $output 'index.html'))) { throw 'Pacote do frontend ausente em output/azure-web.' }

$token = Invoke-AzText @('staticwebapp', 'secrets', 'list', '-g', $resourceGroup, '-n', $site, '--query', 'properties.apiKey')
$ErrorActionPreference = 'Continue'
try {
    $log = & docker run --rm -v "${output}:/site:ro" node:24-bookworm `
        npx --yes '@azure/static-web-apps-cli@2.0.10' deploy /site --env production `
        --deployment-token $token --no-use-keychain 2>&1 | ForEach-Object { "$_" }
} finally { $token = $null }
$ErrorActionPreference = 'Stop'
if (-not ($log -match 'Project deployed to')) {
    $log | Select-Object -Last 8 | Write-Output
    throw 'A SWA CLI nao confirmou a publicacao.'
}

$ErrorActionPreference = 'Continue'
$code = & docker run --rm curlimages/curl:8.11.1 -sS --retry 5 --retry-all-errors -o /dev/null -w '%{http_code}' "https://$hostname/" 2>$null
$ErrorActionPreference = 'Stop'
if ("$code".Trim() -ne '200') { throw "Frontend publicado, mas https://$hostname/ respondeu HTTP $code." }
Write-Output "FRONTEND PUBLICADO: https://$hostname (API $apiBaseUrl)."
