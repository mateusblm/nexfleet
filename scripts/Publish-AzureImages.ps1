[CmdletBinding()]
param(
    [string]$ProfilePath,
    [switch]$SkipBuild,
    [switch]$Authorize
)

# Etapa 5 da publicacao: constroi e publica no ACR as seis imagens Java com a tag de VERSION.
# O login no ACR usa Microsoft Entra ID; o usuario administrador do registro permanece desativado.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $Authorize) { throw 'Execucao bloqueada. Use -Authorize depois da fundacao Azure concluida.' }

$projectRoot = Split-Path -Parent $PSScriptRoot
$azureInfra = Join-Path $projectRoot 'infra/azure'
if ([string]::IsNullOrWhiteSpace($ProfilePath)) { $ProfilePath = Join-Path $azureInfra 'preflight-profile.json' }
$azureProfile = Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
$subscriptionId = [string]$azureProfile.subscriptionId
$resourceGroup = [string]$azureProfile.resourceGroupName
$version = (Get-Content -LiteralPath (Join-Path $projectRoot 'VERSION') -Raw -Encoding UTF8).Trim()
$services = @('gateway', 'bff', 'identidade', 'frota', 'operacoes', 'indicadores')

$ErrorActionPreference = 'Continue'
$registryName = $null
foreach ($attempt in 1..6) {
    $registryName = & az acr list --resource-group $resourceGroup --subscription $subscriptionId `
        --query '[0].name' --output tsv --only-show-errors 2>$null
    if ($LASTEXITCODE -eq 0 -and $registryName) { break }
    Start-Sleep -Seconds (5 * $attempt)
}
if (-not $registryName) { throw 'ACR da homologacao nao encontrado.' }
$registryServer = "$registryName.azurecr.io"

if (-not $SkipBuild) {
    foreach ($service in $services) {
        & docker build --file (Join-Path $projectRoot 'infra/java/Dockerfile') --build-arg "SERVICE=$service" `
            --tag "nexfleet/${service}:$version" $projectRoot
        if ($LASTEXITCODE -ne 0) { throw "Falha ao construir $service." }
    }
}

$loggedIn = $false
foreach ($attempt in 1..6) {
    & az acr login --name $registryName --subscription $subscriptionId --only-show-errors 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $loggedIn = $true; break }
    Start-Sleep -Seconds (5 * $attempt)
}
if (-not $loggedIn) { throw 'Falha no login do ACR por Microsoft Entra ID.' }

$published = [ordered]@{}
foreach ($service in $services) {
    $target = "$registryServer/${service}:$version"
    & docker tag "nexfleet/${service}:$version" $target
    if ($LASTEXITCODE -ne 0) { throw "Imagem local nexfleet/${service}:$version ausente." }
    $ok = $false
    foreach ($attempt in 1..5) {
        & docker push $target | Out-Null
        if ($LASTEXITCODE -eq 0) { $ok = $true; break }
        Write-Output "Push de $service falhou (tentativa $attempt); repetindo."
        Start-Sleep -Seconds (10 * $attempt)
    }
    if (-not $ok) { throw "Falha ao publicar $target." }
    $digest = & docker image inspect $target --format '{{index .RepoDigests 0}}' 2>$null
    $published[$service] = [string]$digest
    Write-Output "Publicada: $target"
}
$ErrorActionPreference = 'Stop'
Write-Output "SEIS IMAGENS PUBLICADAS EM $registryServer com a tag $version."
