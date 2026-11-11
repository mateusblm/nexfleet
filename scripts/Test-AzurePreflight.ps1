[CmdletBinding()]
param(
    [string]$ProfilePath,
    [string]$AzPath,
    [switch]$TemplateOnly,
    [ValidateSet('WhatIf', 'Deployment')]
    [string]$Purpose = 'Deployment'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$azureInfra = Join-Path $projectRoot 'infra/azure'
. (Join-Path $PSScriptRoot 'lib/AzureCli.ps1')
if ([string]::IsNullOrWhiteSpace($ProfilePath)) {
    $ProfilePath = if ($TemplateOnly) {
        Join-Path $azureInfra 'preflight-profile.example.json'
    } else {
        Join-Path $azureInfra 'preflight-profile.json'
    }
}

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

function Require-Property($Object, [string]$Name, [string]$Context) {
    if (-not ($Object.PSObject.Properties.Name -contains $Name)) {
        throw "Propriedade obrigatória ausente em ${Context}: $Name"
    }
}

function Normalize-Location([string]$Value) {
    return (($Value -replace '[^A-Za-z0-9]', '').ToLowerInvariant())
}

$profile = Read-JsonFile $ProfilePath 'Perfil de pré-publicação'
$requirementsPath = Join-Path $azureInfra 'resource-requirements.json'
$requirements = Read-JsonFile $requirementsPath 'Inventário de recursos Azure'

$profileFields = @(
    'schemaVersion', 'environmentName', 'subscriptionId', 'location', 'staticWebLocation', 'resourcePrefix',
    'resourceGroupName', 'monthlyBudgetAmount', 'billingCurrency', 'budgetAlertEmails',
    'budgetThresholdPercent', 'approvals'
)
foreach ($field in $profileFields) { Require-Property $profile $field 'perfil' }
if ([int]$profile.schemaVersion -ne 3) { throw 'schemaVersion do perfil deve ser 3.' }
if ($profile.environmentName -ne 'homolog') { throw 'O primeiro ambiente Azure deve ser homolog.' }

$approvalNames = @(
    'billingScopeChecked', 'spendingProtectionReviewed', 'budgetConfigured',
    'paidResourcesApproved', 'dataRegionApproved', 'quotaReviewed',
    'backupPolicyApproved', 'notificationProviderApproved'
)
foreach ($approval in $approvalNames) { Require-Property $profile.approvals $approval 'approvals' }

Require-Property $requirements 'schemaVersion' 'inventário de recursos'
Require-Property $requirements 'expectedResourceCount' 'inventário de recursos'
Require-Property $requirements 'resources' 'inventário de recursos'
if ([int]$requirements.schemaVersion -ne 2) { throw 'schemaVersion do inventário deve ser 2.' }
$resourceItems = @($requirements.resources)
$expectedResourceCount = [int]$requirements.expectedResourceCount
if ($resourceItems.Count -ne $expectedResourceCount) {
    throw "O inventário Azure deve conter exatamente $expectedResourceCount tipos de recurso; encontrados: $($resourceItems.Count)."
}
$resourceKeys = @{}
foreach ($item in $resourceItems) {
    foreach ($field in @('component', 'namespace', 'resourceType', 'regional')) {
        Require-Property $item $field "recurso $($item.component)"
    }
    $key = "$($item.namespace)/$($item.resourceType)".ToLowerInvariant()
    if ($resourceKeys.ContainsKey($key)) { throw "Tipo de recurso duplicado: $key" }
    $resourceKeys[$key] = $true
}

if ($TemplateOnly) {
    if ($profile.subscriptionId -ne '00000000-0000-0000-0000-000000000000') {
        throw 'O exemplo não deve conter uma assinatura real.'
    }
    if ([decimal]$profile.monthlyBudgetAmount -ne 0) {
        throw 'O exemplo não deve presumir orçamento.'
    }
    foreach ($approval in $approvalNames) {
        if ([bool]$profile.approvals.$approval) {
            throw "O exemplo não pode aprovar antecipadamente: $approval"
        }
    }
    Write-Output "Template de pré-publicação Azure válido: $($resourceItems.Count) tipos de recurso e nenhuma autorização presumida."
    exit 0
}

$problems = [System.Collections.Generic.List[string]]::new()
if ($profile.subscriptionId -notmatch '^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$' -or
    $profile.subscriptionId -eq '00000000-0000-0000-0000-000000000000') {
    $problems.Add('subscriptionId deve conter o UUID real da assinatura escolhida.')
}
if ($profile.location -notmatch '^[a-z0-9]+$' -or $profile.location -eq 'substitua') {
    $problems.Add('location deve conter o nome técnico de uma região, por exemplo brazilsouth.')
}
if ($profile.staticWebLocation -notmatch '^[a-z0-9]+$' -or $profile.staticWebLocation -eq 'substitua') {
    $problems.Add('staticWebLocation deve conter a região validada para Static Web Apps, por exemplo eastus2.')
}
if ($profile.resourcePrefix -notmatch '^[a-z0-9]{3,12}$') {
    $problems.Add('resourcePrefix deve possuir de 3 a 12 caracteres minúsculos ou números.')
}
if ($profile.resourceGroupName -notmatch '^rg-[a-z0-9-]{3,40}$') {
    $problems.Add('resourceGroupName deve começar com rg- e usar somente minúsculas, números e hífen.')
}
if ([decimal]$profile.monthlyBudgetAmount -le 0) {
    $problems.Add('monthlyBudgetAmount deve ser maior que zero e aprovado pela equipe.')
}
if ([string]$profile.billingCurrency -notmatch '^[A-Z]{3}$') {
    $problems.Add('billingCurrency deve usar o código de três letras da moeda da assinatura, como BRL ou USD.')
}
$emails = @($profile.budgetAlertEmails)
if ($emails.Count -lt 1 -or @($emails | Where-Object { $_ -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$' }).Count -gt 0) {
    $problems.Add('budgetAlertEmails deve conter ao menos um e-mail válido.')
}
$thresholds = @($profile.budgetThresholdPercent | ForEach-Object { [int]$_ })
foreach ($requiredThreshold in @(50, 80, 100)) {
    if ($thresholds -notcontains $requiredThreshold) {
        $problems.Add("budgetThresholdPercent deve conter $requiredThreshold%.")
    }
}
foreach ($approval in $approvalNames) {
    if (-not [bool]$profile.approvals.$approval) {
        $requiredForPurpose = $Purpose -eq 'Deployment' -or $approval -in @(
            'billingScopeChecked',
            'spendingProtectionReviewed',
            'budgetConfigured',
            'dataRegionApproved',
            'backupPolicyApproved'
        )
        if ($requiredForPurpose) {
            $problems.Add("Aprovação humana pendente para ${Purpose}: $approval.")
        }
    }
}
if ($problems.Count -gt 0) {
    throw "Pré-publicação bloqueada:`n- $($problems -join "`n- ")"
}

$resolvedAzPath = Resolve-AzureCli -AzPath $AzPath

function Invoke-AzJson([string[]]$Arguments) {
    return Invoke-AzureCliJson -AzPath $resolvedAzPath -Arguments $Arguments
}

$subscriptionId = [string]$profile.subscriptionId
$account = Invoke-AzJson @('account', 'show', '--subscription', $subscriptionId)
if ($account.state -ne 'Enabled') {
    throw "A assinatura selecionada não está Enabled; estado atual: $($account.state)."
}

$defaultAccount = Invoke-AzJson @('account', 'show')
if ([string]$defaultAccount.id -eq $subscriptionId) {
    $locations = Invoke-AzJson @('account', 'list-locations')
} else {
    $locationsResponse = Invoke-AzJson @(
        'rest', '--method', 'get',
        '--url', "https://management.azure.com/subscriptions/$subscriptionId/locations?api-version=2022-12-01"
    )
    $locations = @($locationsResponse.value)
}
$chosenLocation = $locations | Where-Object { $_.name -eq $profile.location } | Select-Object -First 1
if (-not $chosenLocation) {
    throw "A região '$($profile.location)' não aparece em az account list-locations para esta assinatura."
}
$chosenStaticWebLocation = $locations | Where-Object { $_.name -eq $profile.staticWebLocation } | Select-Object -First 1
if (-not $chosenStaticWebLocation) {
    throw "A região '$($profile.staticWebLocation)' do Static Web Apps não aparece para esta assinatura."
}

$results = [System.Collections.Generic.List[object]]::new()
$providers = Invoke-AzJson @('provider', 'list', '--subscription', $subscriptionId)
foreach ($item in $resourceItems) {
    $provider = $providers |
        Where-Object { $_.namespace -eq $item.namespace } |
        Select-Object -First 1
    if (-not $provider) {
        throw "O provedor $($item.namespace) não apareceu no inventário da assinatura."
    }
    $registrationReady = @('Registered', 'Registering') -contains $provider.registrationState
    $resourceType = @($provider.resourceTypes) |
        Where-Object { $_.resourceType -eq $item.resourceType } |
        Select-Object -First 1
    $typeFound = $null -ne $resourceType
    $locationReady = -not [bool]$item.regional
    $targetLocation = if ($item.PSObject.Properties.Name -contains 'locationProfileField') {
        [string]$profile.($item.locationProfileField)
    } else {
        [string]$profile.location
    }
    $targetLocationInfo = $locations | Where-Object { $_.name -eq $targetLocation } | Select-Object -First 1
    if ($typeFound -and [bool]$item.regional) {
        $supported = @($resourceType.locations | ForEach-Object { Normalize-Location ([string]$_) })
        $desiredNames = @(
            Normalize-Location ([string]$targetLocationInfo.name)
            Normalize-Location ([string]$targetLocationInfo.displayName)
            'global'
        )
        $locationReady = @($supported | Where-Object { $desiredNames -contains $_ }).Count -gt 0
    }
    $ready = $registrationReady -and $typeFound -and $locationReady
    $results.Add([pscustomobject]@{
        Component = $item.component
        Provider = $item.namespace
        Type = $item.resourceType
        Registration = $provider.registrationState
        Region = if ($locationReady) { 'OK' } else { 'INDISPONÍVEL' }
        Ready = $ready
    })
}

$results | Format-Table -AutoSize | Out-String | Write-Output
$notReady = @($results | Where-Object { -not $_.Ready })
if ($notReady.Count -gt 0) {
    throw "$($notReady.Count) tipo(s) de recurso não estão prontos. O script não registrou provedores nem criou recursos."
}

$azVersion = Invoke-AzJson @('version')
Write-Output "Azure CLI: $($azVersion.'azure-cli')"
Write-Output "Assinatura: $($account.name) ($subscriptionId)"
Write-Output "Região: $($chosenLocation.displayName) [$($chosenLocation.name)]"
Write-Output "Região do Static Web Apps: $($chosenStaticWebLocation.displayName) [$($chosenStaticWebLocation.name)]"
Write-Output "Orçamento declarado: $($profile.billingCurrency) $($profile.monthlyBudgetAmount) por mês; alertas em 50%, 80% e 100%."
Write-Output "PREFLIGHT AZURE APROVADO PARA $($Purpose.ToUpperInvariant()). Nenhum recurso foi criado ou alterado."
