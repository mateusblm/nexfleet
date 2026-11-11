[CmdletBinding()]
param(
    [string]$AzPath,
    [string]$ReportPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$azureInfra = Join-Path $projectRoot 'infra/azure'
. (Join-Path $PSScriptRoot 'lib/AzureCli.ps1')
$resolvedAzPath = Resolve-AzureCli -AzPath $AzPath

$account = Invoke-AzureCliJson -AzPath $resolvedAzPath -Arguments @('account', 'show')
if ($account.state -ne 'Enabled') {
    throw "A assinatura selecionada nao esta habilitada; estado: $($account.state)."
}
$subscriptionId = [string]$account.id
$scope = "/subscriptions/$subscriptionId"
$assignments = Invoke-AzureCliJson -AzPath $resolvedAzPath -Arguments @(
    'policy', 'assignment', 'list',
    '--scope', $scope,
    '--disable-scope-strict-match', 'true'
)
$regionPolicy = @($assignments | Where-Object {
    $_.name -eq 'sys.regionrestriction' -or
    $_.displayName -eq 'Allowed resource deployment regions'
}) | Select-Object -First 1
if (-not $regionPolicy) {
    throw 'A politica de regioes permitidas nao foi encontrada na assinatura.'
}
$allowedLocations = @($regionPolicy.parameters.listOfAllowedLocations.value | Sort-Object -Unique)
if ($allowedLocations.Count -lt 1) {
    throw 'A politica foi encontrada, mas nao informou regioes permitidas.'
}

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
    $ReportPath = Join-Path $azureInfra "policy-region-report-$timestamp.json"
}
$report = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    mode = 'read-only-policy-discovery'
    subscription = [ordered]@{
        name = [string]$account.name
        state = [string]$account.state
    }
    policy = [ordered]@{
        name = [string]$regionPolicy.name
        displayName = [string]$regionPolicy.displayName
        enforcementMode = [string]$regionPolicy.enforcementMode
        allowedLocations = $allowedLocations
    }
    safety = [ordered]@{
        resourcesCreated = 0
        policiesChanged = 0
        subscriptionChanged = $false
    }
}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $ReportPath -Encoding UTF8

$allowedLocations | ForEach-Object { [pscustomobject]@{ AllowedLocation = $_ } } |
    Format-Table -AutoSize | Out-String | Write-Output
Write-Output "Assinatura: $($account.name) [$($account.state)]"
Write-Output "Relatorio local: $ReportPath"
Write-Output 'POLITICA DE REGIOES CONSULTADA. Nenhum recurso ou politica foi criado, alterado ou excluido.'
