[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^https://')]
    [string]$ApiBaseUrl,
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $projectRoot 'output/azure-web'
}
$resolvedOutput = [IO.Path]::GetFullPath($OutputPath)
$allowedOutputRoot = [IO.Path]::GetFullPath((Join-Path $projectRoot 'output'))
if (-not $resolvedOutput.StartsWith($allowedOutputRoot + [IO.Path]::DirectorySeparatorChar,
        [StringComparison]::OrdinalIgnoreCase)) {
    throw "A saída deve permanecer dentro de $allowedOutputRoot."
}

$projects = @(
    'frontend',
    'microfrontends/frota',
    'microfrontends/operacoes',
    'microfrontends/painel'
)
$oldApiBaseUrl = [Environment]::GetEnvironmentVariable('VITE_API_BASE_URL')
try {
    $env:VITE_API_BASE_URL = $ApiBaseUrl.TrimEnd('/')
    foreach ($project in $projects) {
        Push-Location (Join-Path $projectRoot $project)
        try {
            & npm.cmd run build
            if ($LASTEXITCODE -ne 0) { throw "Falha no build Azure de $project." }
        } finally {
            Pop-Location
        }
    }
} finally {
    if ($null -eq $oldApiBaseUrl) {
        Remove-Item Env:VITE_API_BASE_URL -ErrorAction SilentlyContinue
    } else {
        $env:VITE_API_BASE_URL = $oldApiBaseUrl
    }
}

if (Test-Path -LiteralPath $resolvedOutput) {
    Remove-Item -LiteralPath $resolvedOutput -Recurse -Force
}
New-Item -ItemType Directory -Path $resolvedOutput -Force | Out-Null
Copy-Item -Path (Join-Path $projectRoot 'frontend/dist/*') -Destination $resolvedOutput -Recurse

$mfeRoot = Join-Path $resolvedOutput 'mfes'
foreach ($name in @('frota', 'operacoes', 'painel')) {
    $destination = Join-Path $mfeRoot $name
    New-Item -ItemType Directory -Path $destination -Force | Out-Null
    Copy-Item -Path (Join-Path $projectRoot "microfrontends/$name/dist/*") `
        -Destination $destination -Recurse
}

# Vite separa o CSS de cada biblioteca. O shell publicado precisa carregá-lo
# antes de montar os módulos remotos, sem acrescentar requisições 404 no modo dev.
$indexPath = Join-Path $resolvedOutput 'index.html'
$index = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8
$styles = @(
    '    <link rel="stylesheet" href="/mfes/frota/remoteEntry.css" />',
    '    <link rel="stylesheet" href="/mfes/operacoes/remoteEntry.css" />',
    '    <link rel="stylesheet" href="/mfes/painel/remoteEntry.css" />'
) -join "`n"
$index = $index.Replace('</head>', "$styles`n  </head>")
Set-Content -LiteralPath $indexPath -Value $index -Encoding UTF8

Copy-Item -LiteralPath (Join-Path $projectRoot 'infra/azure/staticwebapp.config.json') `
    -Destination (Join-Path $resolvedOutput 'staticwebapp.config.json')

$manifest = Get-ChildItem -LiteralPath $resolvedOutput -File -Recurse |
    Sort-Object FullName |
    ForEach-Object {
        [ordered]@{
            path = $_.FullName.Substring($resolvedOutput.Length + 1).Replace('\', '/')
            sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        }
    }
$manifest | ConvertTo-Json -Depth 4 | Set-Content `
    -LiteralPath (Join-Path $resolvedOutput 'manifest.sha256.json') -Encoding UTF8

Write-Output "Frontend Azure preparado em: $resolvedOutput"
