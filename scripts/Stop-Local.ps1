[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))

Push-Location $projectRoot
try {
    & docker compose --env-file .env.sprint0 `
        -f compose.sprint0.yaml `
        -f compose.jwt-rsa.yaml down
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao parar o ambiente.' }
} finally {
    Pop-Location
}

Write-Output 'Ambiente parado. Os volumes e bancos locais foram preservados.'
