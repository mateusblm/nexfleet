[CmdletBinding()]
param(
    [string]$ProfilePath,
    [switch]$SkipBuild,
    [switch]$Authorize
)

# Publica a Function NotificarAbastecimento no Flex Consumption (ADR 0037).
# - build limpo (mvnw clean package), para nao carregar pastas legadas do staging;
# - pacote somente com o gatilho Service Bus: o gatilho RabbitMQ e exclusivo do Compose local
#   e, na Azure, gerava "Error indexing method" mesmo desativado;
# - zip com '/' (tar -a): o ZipFile do PowerShell 5.1 grava '\' e o host Linux nao indexa nada;
# - envio pelo endpoint OneDeploy (/api/publish) a partir de um conteiner curl, cuja pilha de
#   rede tolera os resets TLS observados no Windows; o token Entra nao vai para disco.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $Authorize) { throw 'Execucao bloqueada. Use -Authorize depois da fundacao Azure concluida.' }

$projectRoot = Split-Path -Parent $PSScriptRoot
$functionRoot = Join-Path $projectRoot 'functions/notificar-abastecimento'
$azureInfra = Join-Path $projectRoot 'infra/azure'
if ([string]::IsNullOrWhiteSpace($ProfilePath)) { $ProfilePath = Join-Path $azureInfra 'preflight-profile.json' }
$azureProfile = Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
$subscriptionId = [string]$azureProfile.subscriptionId
$resourceGroup = [string]$azureProfile.resourceGroupName
$azureFunctions = @('NotificarAbastecimentoServiceBus')

& docker info *> $null
if ($LASTEXITCODE -ne 0) { throw 'Docker indisponivel: inicie o Docker Desktop (o envio usa um conteiner curl).' }

if (-not $SkipBuild) {
    $localJava = Get-ChildItem (Join-Path $projectRoot '.tools/temurin-jdk-21') -Filter java.exe -File -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not (Get-Command java.exe -ErrorAction SilentlyContinue) -and $localJava) {
        $env:JAVA_HOME = Split-Path -Parent (Split-Path -Parent $localJava.FullName)
        $env:Path = "$env:JAVA_HOME\bin;$env:Path"
    }
    $mavenArgs = @('--batch-mode', '--no-transfer-progress', '-Dmaven.compiler.fork=true')
    $localRepository = Join-Path $projectRoot '.cache/maven-repository'
    if (Test-Path -LiteralPath $localRepository) {
        $env:MAVEN_USER_HOME = Join-Path $projectRoot '.cache/maven-home'
        $mavenArgs += "-Dmaven.repo.local=$localRepository"
    }
    Push-Location $functionRoot
    # Avisos do Maven em stderr (ex.: SLF4J) nao podem virar excecao no PowerShell 5.1.
    $ErrorActionPreference = 'Continue'
    try {
        & (Join-Path $projectRoot 'services/mvnw.cmd') @mavenArgs clean package 2>&1 | ForEach-Object { "$_" }
        if ($LASTEXITCODE -ne 0) { throw 'Falha no build/teste da Function.' }
    } finally {
        $ErrorActionPreference = 'Stop'
        Pop-Location
    }
}

$staging = Get-ChildItem (Join-Path $functionRoot 'target/azure-functions') -Directory -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $staging) { throw 'Pacote da Function ausente; execute sem -SkipBuild.' }

$stage = Join-Path ([IO.Path]::GetTempPath()) "nexfleet-func-$([guid]::NewGuid().ToString('N'))"
$zip = Join-Path ([IO.Path]::GetTempPath()) "nexfleet-func-$([guid]::NewGuid().ToString('N')).zip"
try {
    Copy-Item -LiteralPath $staging.FullName -Destination $stage -Recurse
    Remove-Item -LiteralPath (Join-Path $stage 'local.settings.json') -Force -ErrorAction SilentlyContinue
    foreach ($folder in Get-ChildItem -LiteralPath $stage -Directory) {
        $isFunction = Test-Path -LiteralPath (Join-Path $folder.FullName 'function.json')
        if ($isFunction -and $azureFunctions -notcontains $folder.Name) {
            Remove-Item -LiteralPath $folder.FullName -Recurse -Force
        }
    }
    foreach ($required in $azureFunctions) {
        if (-not (Test-Path -LiteralPath (Join-Path $stage "$required/function.json"))) {
            throw "Funcao $required ausente do pacote."
        }
    }
    Push-Location $stage
    try {
        & tar.exe -a -c -f $zip *
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao gerar o zip da Function.' }
    } finally { Pop-Location }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
        $entries = @($archive.Entries | ForEach-Object { $_.FullName })
    } finally { $archive.Dispose() }
    if (@($entries | Where-Object { $_ -match '\\' }).Count -gt 0) { throw 'Zip com separador invalido (\).' }
    if ($entries -notcontains 'host.json') { throw 'host.json ausente na raiz do pacote.' }

    $ErrorActionPreference = 'Continue'
    $appName = $null
    foreach ($attempt in 1..6) {
        $appName = & az functionapp list -g $resourceGroup --subscription $subscriptionId --query '[0].name' -o tsv --only-show-errors 2>$null
        if ($LASTEXITCODE -eq 0 -and $appName) { break }
        Start-Sleep -Seconds (5 * $attempt)
    }
    if (-not $appName) { throw 'Function App da homologacao nao encontrada.' }
    $token = $null
    foreach ($attempt in 1..6) {
        $token = & az account get-access-token --subscription $subscriptionId --query accessToken -o tsv 2>$null
        if ($LASTEXITCODE -eq 0 -and $token) { break }
        Start-Sleep -Seconds (5 * $attempt)
    }
    if (-not $token) { throw 'Falha ao obter token Microsoft Entra.' }

    $zipDir = Split-Path -Parent $zip
    $zipName = Split-Path -Leaf $zip
    try {
        & docker pull --quiet curlimages/curl:8.11.1 2>$null | Out-Null
        # Argumentos diretos ao curl, sem sh -c: o PowerShell 5.1 corrompe aspas aninhadas.
        $status = & docker run --rm -v "${zipDir}:/pkg:ro" curlimages/curl:8.11.1 `
            -sS --retry 5 --retry-all-errors --max-time 600 -o /dev/null -w '%{http_code}' -X POST `
            -H "Authorization: Bearer $token" -H 'Content-Type: application/zip' `
            --data-binary "@/pkg/$zipName" `
            "https://$appName.scm.azurewebsites.net/api/publish?RemoteBuild=false&Deployer=nexfleet" 2>$null
    } finally { $token = $null }
    if ("$status".Trim() -notin @('200', '202')) { throw "OneDeploy recusou o pacote: HTTP $status" }
    Write-Output "Pacote aceito pelo OneDeploy (HTTP $("$status".Trim()))."

    $deadline = (Get-Date).AddMinutes(6)
    $indexed = @()
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 20
        $list = & az functionapp function list -g $resourceGroup -n $appName --subscription $subscriptionId --query '[].name' -o tsv 2>$null
        if ($LASTEXITCODE -eq 0) {
            $indexed = @($list | ForEach-Object { ($_ -split '/')[-1] })
            if (@($azureFunctions | Where-Object { $indexed -notcontains $_ }).Count -eq 0) { break }
        }
    }
    $ErrorActionPreference = 'Stop'
    $missing = @($azureFunctions | Where-Object { $indexed -notcontains $_ })
    if ($missing.Count -gt 0) { throw "Funcoes nao indexadas apos a publicacao: $($missing -join ', ')" }
    Write-Output "FUNCTION PUBLICADA: $appName com $($indexed -join ', ')."
} finally {
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $zip -Force -ErrorAction SilentlyContinue
}
