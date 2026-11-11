[CmdletBinding()]
param(
    [switch]$ProvisionUser,
    [switch]$NoBuild
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$envPath = Join-Path $projectRoot '.env.sprint0'
$keyPath = Join-Path $projectRoot '.secrets/identidade-jwt.pem'

if (-not (Test-Path -LiteralPath $envPath)) {
    throw 'Execute ./scripts/Initialize-Local.ps1 antes de iniciar o ambiente.'
}
if (-not (Test-Path -LiteralPath $keyPath)) {
    throw 'A chave RSA não existe. Execute ./scripts/Initialize-Local.ps1.'
}
if ($ProvisionUser -and [IO.File]::ReadAllText($envPath).Contains('SUBSTITUA_')) {
    throw 'Defina LOCAL_USER_PASSWORD em .env.sprint0 antes de usar -ProvisionUser.'
}

& docker info --format '{{.ServerVersion}}' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Docker Desktop não está disponível.' }

$base = @(
    'compose', '--env-file', '.env.sprint0',
    '-f', 'compose.sprint0.yaml'
)
$rsa = @('-f', 'compose.jwt-rsa.yaml')
$up = @('up')
if (-not $NoBuild) { $up += '--build' }
$up += @('-d', '--wait')

Push-Location $projectRoot
try {
    if ($ProvisionUser) {
        $previousProfile = $env:IDENTIDADE_PROFILES
        try {
            $env:IDENTIDADE_PROFILES = 'local-seed,jwt-rsa'
            & docker @base '-f' 'compose.sprint1-local.yaml' @rsa @up
            if ($LASTEXITCODE -ne 0) { throw 'Falha ao provisionar o usuário local.' }
        } finally {
            if ($null -eq $previousProfile) {
                Remove-Item Env:IDENTIDADE_PROFILES -ErrorAction SilentlyContinue
            } else {
                $env:IDENTIDADE_PROFILES = $previousProfile
            }
        }

        & docker @base @rsa 'up' '-d' '--wait'
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao retornar Identidade ao modo normal.' }
    } else {
        & docker @base @rsa @up
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao iniciar o ambiente.' }
    }

    & (Join-Path $PSScriptRoot 'Test-Sprint0.ps1')
    & (Join-Path $PSScriptRoot 'Test-Sprint2Eda.ps1')
    & (Join-Path $PSScriptRoot 'Test-Observability.ps1')
} finally {
    Pop-Location
}

Write-Output 'NexFleet disponível em http://127.0.0.1:8080.'
Write-Output 'RabbitMQ disponível em http://127.0.0.1:15672.'
Write-Output 'Prometheus disponível em http://127.0.0.1:9090.'
