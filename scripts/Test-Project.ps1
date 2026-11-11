param(
    [switch]$SkipInstall,
    [switch]$IncludeDatabaseIntegration
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$localNode = Get-ChildItem (Join-Path $projectRoot '.tools') -Directory -Filter 'node-v*-win-x64' -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName 'node.exe') } |
    Sort-Object Name -Descending |
    Select-Object -First 1
$localJava = Get-ChildItem (Join-Path $projectRoot '.tools/temurin-jdk-21') -Filter java.exe -File -Recurse -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not (Get-Command node.exe -ErrorAction SilentlyContinue) -and $localNode) {
    $env:Path = "$($localNode.FullName);$env:Path"
}
if (-not (Get-Command java.exe -ErrorAction SilentlyContinue) -and $localJava) {
    $env:JAVA_HOME = Split-Path -Parent (Split-Path -Parent $localJava.FullName)
    $env:Path = "$env:JAVA_HOME\bin;$env:Path"
}
$mavenArgs = @('--batch-mode', '--no-transfer-progress', '-Dmaven.compiler.fork=true')
$localMavenRepository = Join-Path $projectRoot '.cache/maven-repository'
if (Test-Path -LiteralPath $localMavenRepository) {
    $env:MAVEN_USER_HOME = Join-Path $projectRoot '.cache/maven-home'
    $mavenArgs += "-Dmaven.repo.local=$localMavenRepository"
}
$javaVersion = (& java --version | Select-Object -First 1).ToString()
if ($javaVersion -notmatch '(?:version "|openjdk )21(?:\.|\")') {
    throw "O teste local exige JDK 21. Versão encontrada: $javaVersion"
}

& node (Join-Path $projectRoot 'quality/load/cq09.mjs') --help | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Falha na validacao do executor de desempenho CQ09.' }

& (Join-Path $PSScriptRoot 'Test-AzurePreflight.ps1') -TemplateOnly
if ($LASTEXITCODE -ne 0) { throw 'Falha na validação do template de pré-publicação Azure.' }

& (Join-Path $PSScriptRoot 'Get-AzureReadiness.ps1') -ValidateOnly
if ($LASTEXITCODE -ne 0) { throw 'Falha na validação offline da descoberta Azure.' }

& (Join-Path $PSScriptRoot 'Test-AzureInfrastructure.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Falha na validação offline da infraestrutura Bicep.' }

& (Join-Path $PSScriptRoot 'Test-AzureDatabaseBootstrap.ps1')
if ($LASTEXITCODE -ne 0) { throw 'Falha na validação do isolamento dos bancos Azure.' }

Push-Location (Join-Path $projectRoot 'quality')
try {
    & (Join-Path $projectRoot 'services/mvnw.cmd') @mavenArgs verify
    if ($LASTEXITCODE -ne 0) { throw 'Falha na verificação dos contratos OpenAPI e AsyncAPI.' }
} finally {
    Pop-Location
}

Push-Location (Join-Path $projectRoot 'services')
try {
    & ./mvnw.cmd @mavenArgs verify
    if ($LASTEXITCODE -ne 0) { throw 'Falha na verificação do backend.' }
} finally {
    Pop-Location
}

if ($IncludeDatabaseIntegration) {
    & (Join-Path $PSScriptRoot 'Test-Cq03Cq04.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Falha na prova integrada CQ03/CQ04.' }
    & (Join-Path $PSScriptRoot 'Test-Cq05.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Falha na prova integrada CQ05.' }
    & (Join-Path $PSScriptRoot 'Test-Cq07.ps1')
    if ($LASTEXITCODE -ne 0) { throw 'Falha na prova integrada CQ07.' }
}

Push-Location (Join-Path $projectRoot 'functions/notificar-abastecimento')
try {
    & (Join-Path $projectRoot 'services/mvnw.cmd') @mavenArgs verify
    if ($LASTEXITCODE -ne 0) { throw 'Falha na verificação da função serverless.' }
} finally {
    Pop-Location
}

$frontends = @(
    'frontend',
    'microfrontends/frota',
    'microfrontends/operacoes',
    'microfrontends/painel'
)

foreach ($project in $frontends) {
    Push-Location (Join-Path $projectRoot $project)
    try {
        if (-not $SkipInstall) {
            & npm.cmd ci
            if ($LASTEXITCODE -ne 0) { throw "Falha ao instalar dependências de $project." }
        }
        & npm.cmd test -- --pool=threads --maxWorkers=1
        if ($LASTEXITCODE -ne 0) { throw "Falha nos testes de $project." }
        & npm.cmd run build
        if ($LASTEXITCODE -ne 0) { throw "Falha no build de $project." }
    } finally {
        Pop-Location
    }
}

Write-Output 'Preflight e Bicep Azure, contratos, backend, função serverless, shell e três microfrontends verificados com sucesso.'
