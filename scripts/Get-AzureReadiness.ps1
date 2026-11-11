[CmdletBinding()]
param(
    [string]$SubscriptionId,
    [string[]]$Locations = @('centralus', 'chilecentral', 'mexicocentral', 'northcentralus', 'spaincentral'),
    [string]$ReportPath,
    [string]$AzPath,
    [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$azureInfra = Join-Path $projectRoot 'infra/azure'
$requirementsPath = Join-Path $azureInfra 'resource-requirements.json'
. (Join-Path $PSScriptRoot 'lib/AzureCli.ps1')

function Read-JsonFile([string]$Path, [string]$Description) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Description não encontrado: $Path"
    }
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        throw "$Description possui JSON inválido: $Path. $($_.Exception.Message)"
    }
}

function Normalize-Location([string]$Value) {
    return (($Value -replace '[^A-Za-z0-9]', '').ToLowerInvariant())
}

$requirements = Read-JsonFile $requirementsPath 'Inventário de recursos Azure'
if ([int]$requirements.schemaVersion -ne 2) {
    throw 'O inventário Azure deve usar schemaVersion 2.'
}
$resourceItems = @($requirements.resources)
if ([int]$requirements.expectedResourceCount -ne $resourceItems.Count) {
    throw 'expectedResourceCount não corresponde ao número de recursos do inventário.'
}
if ($Locations.Count -lt 1) {
    throw 'Informe ao menos uma região candidata.'
}
foreach ($location in $Locations) {
    if ($location -notmatch '^[a-z0-9]+$') {
        throw "Região candidata inválida: $location"
    }
}

$resourceKeys = @{}
foreach ($item in $resourceItems) {
    foreach ($field in @('component', 'namespace', 'resourceType', 'regional')) {
        if (-not ($item.PSObject.Properties.Name -contains $field)) {
            throw "Propriedade obrigatória ausente no inventário: $field"
        }
    }
    $key = "$($item.namespace)/$($item.resourceType)".ToLowerInvariant()
    if ($resourceKeys.ContainsKey($key)) {
        throw "Tipo de recurso duplicado: $key"
    }
    $resourceKeys[$key] = $true
}

if ($ValidateOnly) {
    Write-Output "Descoberta Azure válida offline: $($resourceItems.Count) tipos e $($Locations.Count) regiões candidatas."
    exit 0
}

$resolvedAzPath = Resolve-AzureCli -AzPath $AzPath
$accountArguments = @('account', 'show')
if (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) {
    $accountArguments += @('--subscription', $SubscriptionId)
}
$account = Invoke-AzureCliJson -AzPath $resolvedAzPath -Arguments $accountArguments
if ($account.state -ne 'Enabled') {
    throw "A assinatura selecionada não está habilitada; estado atual: $($account.state)."
}
$selectedSubscriptionId = [string]$account.id

$defaultAccount = Invoke-AzureCliJson -AzPath $resolvedAzPath -Arguments @('account', 'show')
if ([string]$defaultAccount.id -eq $selectedSubscriptionId) {
    $availableLocations = Invoke-AzureCliJson -AzPath $resolvedAzPath -Arguments @('account', 'list-locations')
} else {
    $locationsResponse = Invoke-AzureCliJson -AzPath $resolvedAzPath -Arguments @(
        'rest', '--method', 'get',
        '--url', "https://management.azure.com/subscriptions/$selectedSubscriptionId/locations?api-version=2022-12-01"
    )
    $availableLocations = @($locationsResponse.value)
}
$locationResults = foreach ($location in $Locations) {
    $match = $availableLocations | Where-Object { $_.name -eq $location } | Select-Object -First 1
    [pscustomobject]@{
        name = $location
        displayName = if ($match) { [string]$match.displayName } else { $null }
        availableToSubscription = $null -ne $match
    }
}

$providers = Invoke-AzureCliJson -AzPath $resolvedAzPath -Arguments @(
    'provider', 'list', '--subscription', $selectedSubscriptionId
)
$providerCache = @{}
foreach ($namespace in @($resourceItems.namespace | Sort-Object -Unique)) {
    $provider = $providers | Where-Object { $_.namespace -eq $namespace } | Select-Object -First 1
    if (-not $provider) {
        throw "O provedor $namespace não apareceu no inventário da assinatura."
    }
    $providerCache[$namespace] = $provider
}

$resourceResults = foreach ($item in $resourceItems) {
    $provider = $providerCache[[string]$item.namespace]
    $resourceType = @($provider.resourceTypes) |
        Where-Object { $_.resourceType -eq $item.resourceType } |
        Select-Object -First 1
    $supportedLocations = if ($resourceType) {
        @($resourceType.locations | ForEach-Object { Normalize-Location ([string]$_) } | Sort-Object -Unique)
    } else {
        @()
    }
    $regions = [ordered]@{}
    foreach ($location in $Locations) {
        $regions[$location] = (-not [bool]$item.regional) -or
            ($supportedLocations -contains (Normalize-Location $location)) -or
            ($supportedLocations -contains 'global')
    }
    $registrationReady = @('Registered', 'Registering') -contains [string]$provider.registrationState
    [pscustomobject]@{
        component = [string]$item.component
        namespace = [string]$item.namespace
        resourceType = [string]$item.resourceType
        registrationState = [string]$provider.registrationState
        typeFound = $null -ne $resourceType
        supportedLocations = @($supportedLocations)
        candidateRegions = [pscustomobject]$regions
        readyInAnyCandidate = $registrationReady -and ($null -ne $resourceType) -and
            (@($regions.Values | Where-Object { $_ }).Count -gt 0)
    }
}

if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')
    $ReportPath = Join-Path $azureInfra "preflight-report-$timestamp.json"
}
$report = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    mode = 'read-only-discovery'
    subscription = [ordered]@{
        id = $selectedSubscriptionId
        name = [string]$account.name
        state = [string]$account.state
    }
    candidateLocations = @($locationResults)
    resources = @($resourceResults)
    summary = [ordered]@{
        typesChecked = $resourceResults.Count
        providersReady = @($resourceResults | Where-Object {
            $_.registrationState -in @('Registered', 'Registering')
        }).Count
        resourcesReadyInAnyCandidate = @($resourceResults | Where-Object readyInAnyCandidate).Count
    }
    safety = [ordered]@{
        resourcesCreated = 0
        providersRegistered = 0
        subscriptionChanged = $false
    }
}

$reportDirectory = Split-Path -Parent $ReportPath
if ($reportDirectory -and -not (Test-Path -LiteralPath $reportDirectory)) {
    New-Item -ItemType Directory -Path $reportDirectory -Force | Out-Null
}
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $ReportPath -Encoding UTF8

$consoleRows = foreach ($resource in $resourceResults) {
    $row = [ordered]@{
        Component = $resource.component
        Provider = $resource.registrationState
        Type = if ($resource.typeFound) { 'OK' } else { 'AUSENTE' }
    }
    foreach ($location in $Locations) {
        $row[$location] = if ([bool]$resource.candidateRegions.$location) { 'SIM' } else { 'NÃO' }
    }
    [pscustomobject]$row
}
$consoleRows | Format-Table -AutoSize | Out-String | Write-Output
Write-Output "Assinatura: $($account.name) [$($account.state)]"
Write-Output "Tipos verificados: $($report.summary.typesChecked); prontos em alguma região candidata: $($report.summary.resourcesReadyInAnyCandidate)."
Write-Output "Relatório local: $ReportPath"
Write-Output 'DESCOBERTA AZURE CONCLUÍDA. Nenhum recurso ou provedor foi criado, registrado ou alterado.'
