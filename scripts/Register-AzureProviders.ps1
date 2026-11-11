[CmdletBinding()]
param(
    [string]$SubscriptionId,
    [string]$AzPath,
    [switch]$Authorize,
    [switch]$IncludeNetwork
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $Authorize) {
    throw 'Registro bloqueado. Use -Authorize somente após aprovação explícita para alterar a assinatura.'
}

. (Join-Path $PSScriptRoot 'lib/AzureCli.ps1')
$resolvedAzPath = Resolve-AzureCli -AzPath $AzPath
$accountArguments = @('account', 'show')
if (-not [string]::IsNullOrWhiteSpace($SubscriptionId)) {
    $accountArguments += @('--subscription', $SubscriptionId)
}
$account = Invoke-AzureCliJson -AzPath $resolvedAzPath -Arguments $accountArguments
if ($account.state -ne 'Enabled') {
    throw "A assinatura não está habilitada; estado: $($account.state)."
}

$namespaces = @(
    'Microsoft.ApiManagement',
    'Microsoft.ContainerRegistry',
    'Microsoft.DBforPostgreSQL',
    'Microsoft.KeyVault',
    'Microsoft.ManagedIdentity'
)
if ($IncludeNetwork) {
    $namespaces += 'Microsoft.Network'
}
$providers = Invoke-AzureCliJson -AzPath $resolvedAzPath -Arguments @(
    'provider', 'list', '--subscription', [string]$account.id
)

foreach ($namespace in $namespaces) {
    $provider = $providers | Where-Object { $_.namespace -eq $namespace } | Select-Object -First 1
    if ($provider.registrationState -eq 'Registered') {
        Write-Output "$namespace já estava Registered."
        continue
    }

    $registered = $false
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $previousErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $raw = & $resolvedAzPath provider register `
                --namespace $namespace `
                --subscription ([string]$account.id) `
                --output none `
                --only-show-errors 2>&1
            $exitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
        if ($exitCode -eq 0) {
            $registered = $true
            break
        }

        # Uma queda de conexÃ£o pode acontecer depois de a Azure aceitar a
        # solicitaÃ§Ã£o. Conferir o estado evita repetir uma mutaÃ§Ã£o concluÃ­da.
        $current = Invoke-AzureCliJson -AzPath $resolvedAzPath -Arguments @(
            'provider', 'show', '--namespace', $namespace,
            '--subscription', [string]$account.id
        )
        if ([string]$current.registrationState -in @('Registered', 'Registering')) {
            $registered = $true
            break
        }
        if ($attempt -lt 3) { Start-Sleep -Seconds $attempt }
    }
    if (-not $registered) {
        $safeOutput = (($raw -join "`n") -replace [regex]::Escape([string]$account.id), '<subscription-id>')
        throw "Falha ao solicitar o registro de ${namespace} apÃ³s 3 tentativas: $safeOutput"
    }
    Write-Output "${namespace}: registro solicitado."
}

Write-Output 'Solicitações concluídas. O registro de provedor não cria serviços ou cargas de trabalho.'
