[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [switch]$SkipServerless,
    [switch]$SkipObservability,
    [switch]$IncludePerformance,
    [switch]$IncludeRecovery
)

$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'Test-Sprint0.ps1') -Port ([uri]$BaseUrl).Port
& (Join-Path $PSScriptRoot 'Test-ApiContracts.ps1') -BaseUrl $BaseUrl
& (Join-Path $PSScriptRoot 'Test-Sprint2Eda.ps1')
if (-not $SkipServerless) {
    & (Join-Path $PSScriptRoot 'Test-Sprint3Serverless.ps1')
}
if (-not $SkipObservability) {
    & (Join-Path $PSScriptRoot 'Test-Observability.ps1')
}
if ($IncludePerformance) {
    & (Join-Path $PSScriptRoot 'Test-Performance.ps1') -BaseUrl $BaseUrl
}
if ($IncludeRecovery) {
    & (Join-Path $PSScriptRoot 'Test-Recovery.ps1')
}

Write-Output 'E2E aprovado: Gateway, BFF, microsserviços, bancos, RabbitMQ, Function e métricas.'
