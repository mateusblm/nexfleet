[CmdletBinding()]
param(
    [string]$ProfilePath,
    [string]$Location,
    [decimal]$HoursPerMonth = 730,
    [decimal]$DaysPerMonth = 30.4375,
    [string]$OutputPath,
    [switch]$AsJson
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$azureInfra = Join-Path $projectRoot 'infra/azure'
if ([string]::IsNullOrWhiteSpace($ProfilePath)) {
    $ProfilePath = Join-Path $azureInfra 'preflight-profile.json'
}

function Read-JsonFile([string]$Path, [string]$Description) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Description nao encontrado: $Path"
    }
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        throw "$Description possui JSON invalido: $Path. $($_.Exception.Message)"
    }
}

function Get-RetailItems([string]$CurrencyCode, [string]$Filter) {
    $encodedFilter = [uri]::EscapeDataString($Filter)
    $nextPage = "https://prices.azure.com/api/retail/prices?currencyCode=$CurrencyCode&`$filter=$encodedFilter"
    $items = [System.Collections.Generic.List[object]]::new()
    while (-not [string]::IsNullOrWhiteSpace($nextPage)) {
        $response = Invoke-RestMethod -Uri $nextPage -Method Get
        foreach ($item in @($response.Items)) { $items.Add($item) }
        $nextPage = [string]$response.NextPageLink
    }
    return @($items)
}

function Find-PaidMeter(
    [object[]]$Items,
    [string]$ProductName,
    [string]$SkuName,
    [string]$MeterName,
    [string]$UnitOfMeasure = ''
) {
    $matches = @($Items | Where-Object {
        $_.type -eq 'Consumption' -and
        $_.productName -eq $ProductName -and
        $_.skuName -eq $SkuName -and
        $_.meterName -eq $MeterName -and
        ([string]::IsNullOrWhiteSpace($UnitOfMeasure) -or $_.unitOfMeasure -eq $UnitOfMeasure) -and
        [decimal]$_.retailPrice -gt 0
    })
    if ($matches.Count -ne 1) {
        throw "Medidor nao foi resolvido de forma unica: $ProductName / $SkuName / $MeterName. Encontrados: $($matches.Count)."
    }
    return $matches[0]
}

function Round-Money([decimal]$Value) {
    return [decimal]::Round($Value, 2, [MidpointRounding]::AwayFromZero)
}

$profile = Read-JsonFile $ProfilePath 'Perfil Azure'
if ([string]$profile.billingCurrency -ne 'BRL') {
    throw 'A estimativa versionada desta etapa espera billingCurrency=BRL.'
}
if ([string]::IsNullOrWhiteSpace($Location)) {
    $Location = [string]$profile.location
}
if ($Location -notmatch '^[a-z0-9]+$') {
    throw "Location invalida: $Location"
}

$postgresFilter = "serviceName eq 'Azure Database for PostgreSQL' and armRegionName eq '$Location'"
$serviceBusFilter = "serviceName eq 'Service Bus' and armRegionName eq '$Location'"
$registryFilter = "serviceName eq 'Container Registry' and armRegionName eq '$Location'"
$containerAppsFilter = "serviceName eq 'Azure Container Apps' and armRegionName eq '$Location'"

$postgresBrl = Get-RetailItems 'BRL' $postgresFilter
$serviceBusBrl = Get-RetailItems 'BRL' $serviceBusFilter
$serviceBusUsd = Get-RetailItems 'USD' $serviceBusFilter
$registryBrl = Get-RetailItems 'BRL' $registryFilter
$containerAppsUsd = Get-RetailItems 'USD' $containerAppsFilter

$postgresCompute = Find-PaidMeter $postgresBrl `
    'Azure Database for PostgreSQL Flexible Server Burstable BS Series Compute' 'B1MS' 'B1MS'
$postgresStorage = Find-PaidMeter $postgresBrl `
    'Azure Database for PostgreSQL Flex Server Storage' 'Storage' 'Storage Data Stored'
$serviceBusBaseBrl = Find-PaidMeter $serviceBusBrl `
    'Service Bus' 'Standard' 'Standard Base Unit' '1/Month'
$serviceBusBaseUsd = Find-PaidMeter $serviceBusUsd `
    'Service Bus' 'Standard' 'Standard Base Unit' '1/Month'
$registryBasic = Find-PaidMeter $registryBrl `
    'Container Registry' 'Basic' 'Basic Registry Unit'
$cpuIdle = Find-PaidMeter $containerAppsUsd `
    'Azure Container Apps' 'Standard' 'Standard vCPU Idle Usage'
$cpuActive = Find-PaidMeter $containerAppsUsd `
    'Azure Container Apps' 'Standard' 'Standard vCPU Active Usage'
$memoryIdle = Find-PaidMeter $containerAppsUsd `
    'Azure Container Apps' 'Standard' 'Standard Memory Idle Usage'
$memoryActive = Find-PaidMeter $containerAppsUsd `
    'Azure Container Apps' 'Standard' 'Standard Memory Active Usage'

$containerModule = Get-Content -LiteralPath (Join-Path $azureInfra 'modules/container-app.bicep') -Raw -Encoding UTF8
$workloadsModule = Get-Content -LiteralPath (Join-Path $azureInfra 'modules/workloads.bicep') -Raw -Encoding UTF8
$cpuMatch = [regex]::Match($containerModule, "cpu:\s*json\('(?<value>[0-9.]+)'\)")
$memoryMatch = [regex]::Match($containerModule, "memory:\s*'(?<value>[0-9.]+)Gi'")
$replicaMatches = [regex]::Matches($workloadsModule, 'minReplicas:\s*(?<value>\d+)')
if (-not $cpuMatch.Success -or -not $memoryMatch.Success -or $replicaMatches.Count -ne 6) {
    throw 'Nao foi possivel extrair CPU, memoria e as seis configuracoes minReplicas do Bicep.'
}
$cpuPerReplica = [decimal]::Parse($cpuMatch.Groups['value'].Value, [Globalization.CultureInfo]::InvariantCulture)
$memoryPerReplicaGiB = [decimal]::Parse($memoryMatch.Groups['value'].Value, [Globalization.CultureInfo]::InvariantCulture)
$minimumReplicas = [decimal](($replicaMatches | ForEach-Object { [int]$_.Groups['value'].Value } | Measure-Object -Sum).Sum)

$secondsPerMonth = $HoursPerMonth * 3600
$freeVcpuSeconds = [decimal]180000
$freeMemoryGiBSeconds = [decimal]360000
$allocatedVcpuSeconds = $minimumReplicas * $cpuPerReplica * $secondsPerMonth
$allocatedMemoryGiBSeconds = $minimumReplicas * $memoryPerReplicaGiB * $secondsPerMonth
$billableVcpuSeconds = if ($allocatedVcpuSeconds -gt $freeVcpuSeconds) {
    $allocatedVcpuSeconds - $freeVcpuSeconds
} else { [decimal]0 }
$billableMemoryGiBSeconds = if ($allocatedMemoryGiBSeconds -gt $freeMemoryGiBSeconds) {
    $allocatedMemoryGiBSeconds - $freeMemoryGiBSeconds
} else { [decimal]0 }
$brlPerUsd = [decimal]$serviceBusBaseBrl.retailPrice / [decimal]$serviceBusBaseUsd.retailPrice

$postgresComputeMonthly = [decimal]$postgresCompute.retailPrice * $HoursPerMonth
$postgresStorageMonthly = [decimal]$postgresStorage.retailPrice * 32
$serviceBusMonthly = [decimal]$serviceBusBaseBrl.retailPrice
$registryMonthly = [decimal]$registryBasic.retailPrice * $DaysPerMonth
$fixedMonthly = $postgresComputeMonthly + $postgresStorageMonthly + $serviceBusMonthly + $registryMonthly
$containerIdleUsd = ($billableVcpuSeconds * [decimal]$cpuIdle.retailPrice) +
    ($billableMemoryGiBSeconds * [decimal]$memoryIdle.retailPrice)
$containerActiveUsd = ($billableVcpuSeconds * [decimal]$cpuActive.retailPrice) +
    ($billableMemoryGiBSeconds * [decimal]$memoryActive.retailPrice)
$containerIdleBrl = $containerIdleUsd * $brlPerUsd
$containerActiveBrl = $containerActiveUsd * $brlPerUsd

$report = [ordered]@{
    schemaVersion = 1
    generatedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
    source = 'Azure Retail Prices API'
    sourceUrl = 'https://prices.azure.com/api/retail/prices'
    region = $Location
    currency = 'BRL'
    assumptions = [ordered]@{
        hoursPerMonth = $HoursPerMonth
        daysPerMonth = $DaysPerMonth
        postgresqlSku = 'Standard_B1ms'
        postgresqlStorageGiB = 32
        serviceBusSku = 'Standard'
        containerRegistrySku = 'Basic'
        minimumContainerReplicas = $minimumReplicas
        cpuPerReplica = $cpuPerReplica
        memoryGiBPerReplica = $memoryPerReplicaGiB
        containerAppsFreeGrantAssumedAvailable = $true
        creditsOrStudentBenefitsApplied = $false
    }
    monthlyEstimate = [ordered]@{
        postgresqlCompute = Round-Money $postgresComputeMonthly
        postgresqlStorage = Round-Money $postgresStorageMonthly
        serviceBusBase = Round-Money $serviceBusMonthly
        containerRegistryBasic = Round-Money $registryMonthly
        fixedSubtotal = Round-Money $fixedMonthly
        containerAppsAllMinimumReplicasIdle = Round-Money $containerIdleBrl
        containerAppsAllMinimumReplicasActive = Round-Money $containerActiveBrl
        lowerBound = Round-Money ($fixedMonthly + $containerIdleBrl)
        upperReference = Round-Money ($fixedMonthly + $containerActiveBrl)
        declaredBudget = [decimal]$profile.monthlyBudgetAmount
    }
    exclusions = @(
        'Log Analytics e Application Insights acima das franquias',
        'API Management, Function, Storage e Key Vault por uso',
        'Private DNS, transferencia de dados, impostos e variacao cambial',
        'replicas adicionais por autoscaling',
        'Azure Communication Services Email',
        'descontos, creditos e beneficios Azure for Students'
    )
    safety = [ordered]@{
        azureAccountAccessed = $false
        resourcesCreated = 0
        subscriptionChanged = $false
    }
}

$json = $report | ConvertTo-Json -Depth 8
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $outputDirectory = Split-Path -Parent $OutputPath
    if ($outputDirectory -and -not (Test-Path -LiteralPath $outputDirectory)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }
    $json | Set-Content -LiteralPath $OutputPath -Encoding UTF8
}

if ($AsJson) {
    Write-Output $json
    exit 0
}

$rows = @(
    [pscustomobject]@{ Item = 'PostgreSQL B1ms - computacao'; BRL = Round-Money $postgresComputeMonthly },
    [pscustomobject]@{ Item = 'PostgreSQL - 32 GiB'; BRL = Round-Money $postgresStorageMonthly },
    [pscustomobject]@{ Item = 'Service Bus Standard - base'; BRL = Round-Money $serviceBusMonthly },
    [pscustomobject]@{ Item = 'Container Registry Basic'; BRL = Round-Money $registryMonthly },
    [pscustomobject]@{ Item = 'Container Apps - 3 replicas ociosas'; BRL = Round-Money $containerIdleBrl },
    [pscustomobject]@{ Item = 'Container Apps - 3 replicas ativas'; BRL = Round-Money $containerActiveBrl }
)
$rows | Format-Table -AutoSize | Out-String | Write-Output
Write-Output "Faixa mensal parcial, sem creditos: BRL $((Round-Money ($fixedMonthly + $containerIdleBrl)).ToString('F2')) a BRL $((Round-Money ($fixedMonthly + $containerActiveBrl)).ToString('F2'))."
Write-Output "Orcamento declarado: BRL $([decimal]$profile.monthlyBudgetAmount)."
Write-Output 'ESTIMATIVA CONCLUIDA. Somente a API publica de precos foi consultada; nenhum recurso Azure foi criado ou alterado.'
