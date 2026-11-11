[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://127.0.0.1:8080',
    [ValidateRange(1, 1000)][int]$Users = 100,
    [ValidateRange(1, 1000)][int]$Iterations = 3,
    [ValidateRange(1, 100)][int]$PageSize = 20,
    [ValidateRange(1, 2147483647)][int]$ThresholdMs = 2000,
    [ValidateRange(1, 2147483647)][int]$TimeoutMs = 10000,
    [ValidateRange(0, 100)][int]$Warmup = 2
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$envPath = Join-Path $projectRoot '.env.sprint0'
$loadScript = Join-Path $projectRoot 'quality/load/cq09.mjs'

if (-not (Test-Path -LiteralPath $envPath)) {
    throw 'Execute ./scripts/Initialize-Local.ps1 antes do teste de desempenho.'
}

$settings = @{}
foreach ($line in [IO.File]::ReadAllLines($envPath)) {
    if ([String]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
    $parts = $line.Split('=', 2)
    if ($parts.Count -eq 2) { $settings[$parts[0].Trim()] = $parts[1].Trim() }
}

$email = $settings['LOCAL_USER_EMAIL']
$password = $settings['LOCAL_USER_PASSWORD']
if ([String]::IsNullOrWhiteSpace($email) -or
    [String]::IsNullOrWhiteSpace($password) -or
    $password.StartsWith('SUBSTITUA_')) {
    throw 'Defina LOCAL_USER_EMAIL e LOCAL_USER_PASSWORD em .env.sprint0.'
}

$nodeCommand = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeCommand) { $nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue }
if (-not $nodeCommand -and $IsWindows -ne $false) {
    $localNode = Get-ChildItem (Join-Path $projectRoot '.tools') -Directory `
        -Filter 'node-v*-win-x64' -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName 'node.exe') } |
        Sort-Object Name -Descending |
        Select-Object -First 1
    if ($localNode) {
        $nodeCommand = Get-Item (Join-Path $localNode.FullName 'node.exe')
    }
}
if (-not $nodeCommand) {
    throw 'Node.js 20 ou superior nao foi encontrado. Execute ./scripts/Install-Dependencies.ps1.'
}

$nodeExecutable = $nodeCommand.Source
if ([String]::IsNullOrWhiteSpace($nodeExecutable)) { $nodeExecutable = $nodeCommand.FullName }
$nodeMajor = [int]((& $nodeExecutable --version).TrimStart('v').Split('.')[0])
if ($nodeMajor -lt 20) { throw "O teste de desempenho exige Node.js 20 ou superior; encontrado: $nodeMajor." }

$previousEmail = [Environment]::GetEnvironmentVariable('NEXFLEET_LOAD_EMAIL', 'Process')
$previousPassword = [Environment]::GetEnvironmentVariable('NEXFLEET_LOAD_PASSWORD', 'Process')
try {
    [Environment]::SetEnvironmentVariable('NEXFLEET_LOAD_EMAIL', $email, 'Process')
    [Environment]::SetEnvironmentVariable('NEXFLEET_LOAD_PASSWORD', $password, 'Process')
    & $nodeExecutable $loadScript `
        --base-url $BaseUrl `
        --users $Users `
        --iterations $Iterations `
        --page-size $PageSize `
        --threshold-ms $ThresholdMs `
        --timeout-ms $TimeoutMs `
        --warmup $Warmup
    if ($LASTEXITCODE -ne 0) { throw 'O criterio CQ09 nao foi atendido.' }
} finally {
    [Environment]::SetEnvironmentVariable('NEXFLEET_LOAD_EMAIL', $previousEmail, 'Process')
    [Environment]::SetEnvironmentVariable('NEXFLEET_LOAD_PASSWORD', $previousPassword, 'Process')
}
