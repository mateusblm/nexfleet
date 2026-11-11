# LEGADO (v0.30.0): para compose.sprint0.yaml + compose.jwt-rsa.yaml.
# Nao funciona com o layout da v1.0.0 (guarda-chuva + repositorios nexfleet-*, compose.yaml,
# SQL Server e MongoDB) e fica apenas como historico. Na v1.0.0: docker compose down.

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
