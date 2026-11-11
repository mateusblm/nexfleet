[CmdletBinding()]
param(
    [string]$ProfilePath,
    [string]$AzPath,
    [switch]$Authorize
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $Authorize) {
    throw 'Orçamento bloqueado. Use -Authorize somente após aprovar valor, moeda e destinatários.'
}

$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ProfilePath)) {
    $ProfilePath = Join-Path $projectRoot 'infra/azure/preflight-profile.json'
}
if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) {
    throw "Perfil Azure real não encontrado: $ProfilePath"
}
$profile = Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int]$profile.schemaVersion -ne 3) { throw 'O perfil Azure deve usar schemaVersion 3.' }
if ([decimal]$profile.monthlyBudgetAmount -le 0) { throw 'O orçamento mensal deve ser maior que zero.' }
if ([string]$profile.billingCurrency -notmatch '^[A-Z]{3}$') { throw 'A moeda deve possuir três letras.' }
$emails = @($profile.budgetAlertEmails)
if ($emails.Count -lt 1) { throw 'Informe ao menos um destinatário de alerta.' }
if (-not [bool]$profile.approvals.billingScopeChecked -or
    -not [bool]$profile.approvals.spendingProtectionReviewed) {
    throw 'Confira o escopo de cobrança e a proteção de gastos antes de criar o orçamento.'
}

. (Join-Path $PSScriptRoot 'lib/AzureCli.ps1')
$resolvedAzPath = Resolve-AzureCli -AzPath $AzPath
$account = Invoke-AzureCliJson -AzPath $resolvedAzPath -Arguments @(
    'account', 'show', '--subscription', [string]$profile.subscriptionId
)
if ($account.state -ne 'Enabled') { throw 'A assinatura selecionada não está habilitada.' }

$startDate = Get-Date -Year (Get-Date).Year -Month (Get-Date).Month -Day 1 -Hour 0 -Minute 0 -Second 0
$endDate = $startDate.AddYears(1)
$budgetName = "$($profile.resourcePrefix)-$($profile.environmentName)-monthly"
$budgetId = "/subscriptions/$($profile.subscriptionId)/providers/Microsoft.Consumption/budgets/$budgetName"
$url = "https://management.azure.com${budgetId}?api-version=2024-08-01"
$payload = [ordered]@{
    properties = [ordered]@{
        category = 'Cost'
        amount = [decimal]$profile.monthlyBudgetAmount
        timeGrain = 'Monthly'
        timePeriod = [ordered]@{
            startDate = $startDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            endDate = $endDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
        filter = [ordered]@{
            dimensions = [ordered]@{
                name = 'ResourceGroupName'
                operator = 'In'
                values = @([string]$profile.resourceGroupName)
            }
        }
        notifications = [ordered]@{
            Actual_50_Percent = [ordered]@{
                enabled = $true
                operator = 'GreaterThanOrEqualTo'
                threshold = 50
                thresholdType = 'Actual'
                contactEmails = $emails
                contactRoles = @()
                contactGroups = @()
                locale = 'en-us'
            }
            Actual_80_Percent = [ordered]@{
                enabled = $true
                operator = 'GreaterThanOrEqualTo'
                threshold = 80
                thresholdType = 'Actual'
                contactEmails = $emails
                contactRoles = @()
                contactGroups = @()
                locale = 'en-us'
            }
            Forecast_100_Percent = [ordered]@{
                enabled = $true
                operator = 'GreaterThanOrEqualTo'
                threshold = 100
                thresholdType = 'Forecasted'
                contactEmails = $emails
                contactRoles = @()
                contactGroups = @()
                locale = 'en-us'
            }
        }
    }
}

$temporaryBody = Join-Path ([System.IO.Path]::GetTempPath()) "nexfleet-budget-$([guid]::NewGuid().ToString('N')).json"
try {
    $payload | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $temporaryBody -Encoding UTF8
    $result = Invoke-AzureCliJson -AzPath $resolvedAzPath -Arguments @(
        'rest', '--method', 'put', '--url', $url, '--body', "@$temporaryBody"
    )
    if ([string]$result.name -ne $budgetName) { throw 'A Azure devolveu um orçamento inesperado.' }
} finally {
    Remove-Item -LiteralPath $temporaryBody -Force -ErrorAction SilentlyContinue
}

Write-Output "Orçamento configurado: $($profile.billingCurrency) $($profile.monthlyBudgetAmount)/mês."
Write-Output 'Alertas: 50% real, 80% real e 100% previsto.'
Write-Output 'O orçamento apenas alerta; ele não interrompe recursos automaticamente.'
