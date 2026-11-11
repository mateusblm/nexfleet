Set-StrictMode -Version Latest

function Resolve-AzureCli {
    [CmdletBinding()]
    param(
        [string]$AzPath
    )

    if (-not [string]::IsNullOrWhiteSpace($AzPath)) {
        if (-not (Test-Path -LiteralPath $AzPath -PathType Leaf)) {
            throw "Azure CLI não encontrado no caminho informado: $AzPath"
        }
        return (Resolve-Path -LiteralPath $AzPath).Path
    }

    $command = Get-Command az -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidates = @(
        (Join-Path $env:ProgramFiles 'Microsoft SDKs/Azure/CLI2/wbin/az.cmd')
    )
    if (${env:ProgramFiles(x86)}) {
        $candidates += Join-Path ${env:ProgramFiles(x86)} 'Microsoft SDKs/Azure/CLI2/wbin/az.cmd'
    }
    if ($env:LOCALAPPDATA) {
        $candidates += Join-Path $env:LOCALAPPDATA 'Programs/Azure CLI/wbin/az.cmd'
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }

    throw 'Azure CLI não encontrado. Instale a ferramenta oficial, reabra o terminal e execute az login.'
}

function Invoke-AzureCliJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AzPath,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [ValidateRange(1, 5)]
        [int]$MaxAttempts = 3
    )

    $subscriptionPattern = '[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}'
    $safeArguments = (($Arguments -join ' ') -replace $subscriptionPattern, '<subscription-id>')

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        $previousErrorActionPreference = $ErrorActionPreference
        try {
            # O Windows PowerShell 5.1 converte o stderr de programas nativos em
            # NativeCommandError quando a preferência global está em Stop. A
            # decisão precisa usar o exit code do Azure CLI para permitir retry.
            $ErrorActionPreference = 'Continue'
            $raw = & $AzPath @Arguments '--only-show-errors' '--output' 'json' 2>&1
            $exitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
        if ($exitCode -eq 0) {
            try {
                return ($raw -join "`n") | ConvertFrom-Json
            } catch {
                throw "Azure CLI devolveu JSON inválido em: az $safeArguments"
            }
        }

        if ($attempt -lt $MaxAttempts) {
            Start-Sleep -Seconds $attempt
            continue
        }

        $safeOutput = (($raw -join "`n") -replace $subscriptionPattern, '<subscription-id>')
        throw "Azure CLI falhou após $MaxAttempts tentativa(s) em: az $safeArguments`n$safeOutput"
    }
}
