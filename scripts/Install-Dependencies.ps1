[CmdletBinding()]
param(
    [switch]$SkipRuntimeDownload,
    [switch]$SkipDockerImages
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$toolsRoot = Join-Path $projectRoot '.tools'
$cacheRoot = Join-Path $projectRoot '.cache'
$downloadRoot = Join-Path $cacheRoot 'downloads'
$mavenHome = Join-Path $cacheRoot 'maven-home'
$mavenRepository = Join-Path $cacheRoot 'maven-repository'

@($toolsRoot, $downloadRoot, $mavenHome, $mavenRepository) | ForEach-Object {
    New-Item -ItemType Directory -Force -Path $_ | Out-Null
}

function Get-NodeHome {
    $systemNode = Get-Command node.exe -ErrorAction SilentlyContinue
    if ($systemNode) {
        $major = (& $systemNode.Source --version).TrimStart('v').Split('.')[0]
        if ($major -eq '24') {
            return Split-Path -Parent $systemNode.Source
        }
    }

    $version = '24.22.2'
    $directory = Join-Path $toolsRoot "node-v$version-win-x64"
    if (Test-Path -LiteralPath (Join-Path $directory 'node.exe')) {
        return $directory
    }
    if ($SkipRuntimeDownload) {
        throw 'Node.js 24 não foi encontrado e o download de runtimes foi desativado.'
    }

    $fileName = "node-v$version-win-x64.zip"
    $archive = Join-Path $downloadRoot $fileName
    $baseUrl = 'https://nodejs.org/download/release/latest-v24.x'
    $checksums = Join-Path $downloadRoot 'node-SHASUMS256.txt'
    Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/$fileName" -OutFile $archive
    Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/SHASUMS256.txt" -OutFile $checksums
    $checksumLine = Get-Content $checksums | Where-Object { $_ -match [Regex]::Escape($fileName) }
    if (-not $checksumLine) { throw 'Checksum oficial do Node.js não encontrado.' }
    $expected = ($checksumLine -split '\s+')[0].ToUpperInvariant()
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash
    if ($actual -ne $expected) { throw 'Checksum do Node.js não confere.' }
    Expand-Archive -LiteralPath $archive -DestinationPath $toolsRoot -Force
    return $directory
}

function Get-JavaHome {
    $systemJava = Get-Command java.exe -ErrorAction SilentlyContinue
    if ($systemJava) {
        $versionLine = (& $systemJava.Source -version 2>&1 | Select-Object -First 1).ToString()
        if ($versionLine -match 'version "21(?:\.|\")') {
            return Split-Path -Parent (Split-Path -Parent $systemJava.Source)
        }
    }

    $directory = Join-Path $toolsRoot 'temurin-jdk-21'
    $existingJava = Get-ChildItem -LiteralPath $directory -Filter java.exe -File -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($existingJava) {
        return Split-Path -Parent (Split-Path -Parent $existingJava.FullName)
    }
    if ($SkipRuntimeDownload) {
        throw 'JDK 21 não foi encontrado e o download de runtimes foi desativado.'
    }

    $api = 'https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture=x64&heap_size=normal&image_type=jdk&jvm_impl=hotspot&os=windows&vendor=eclipse'
    $assets = Invoke-RestMethod -Uri $api -Headers @{ 'User-Agent' = 'NexFleet-Dependency-Installer' }
    $package = @($assets)[0].binary.package
    if (-not $package.link -or -not $package.checksum) {
        throw 'A API do Eclipse Adoptium não retornou um JDK 21 válido.'
    }
    $archive = Join-Path $downloadRoot 'temurin-jdk-21-windows-x64.zip'
    Invoke-WebRequest -UseBasicParsing -Uri $package.link -OutFile $archive
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash
    if ($actual -ne $package.checksum.ToUpperInvariant()) {
        throw 'Checksum do JDK 21 não confere.'
    }
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    Expand-Archive -LiteralPath $archive -DestinationPath $directory -Force
    $java = Get-ChildItem -LiteralPath $directory -Filter java.exe -File -Recurse |
        Select-Object -First 1
    if (-not $java) { throw 'java.exe não foi encontrado depois da extração do JDK.' }
    return Split-Path -Parent (Split-Path -Parent $java.FullName)
}

function Get-BicepPath {
    $systemBicep = Get-Command bicep.exe -ErrorAction SilentlyContinue
    if ($systemBicep) {
        return $systemBicep.Source
    }

    $version = '0.49.2'
    $directory = Join-Path $toolsRoot 'bicep'
    $executable = Join-Path $directory 'bicep.exe'
    if (Test-Path -LiteralPath $executable -PathType Leaf) {
        return $executable
    }
    if ($SkipRuntimeDownload) {
        throw 'Bicep CLI não foi encontrado e o download de runtimes foi desativado.'
    }

    $expected = 'ACFFF0453C9BCF442AA97103ACBCD845EF366634E6EA2A2BA5734514409CE9C3'
    $uri = "https://github.com/Azure/bicep/releases/download/v$version/bicep-win-x64.exe"
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $executable
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $executable).Hash
    if ($actual -ne $expected) {
        Remove-Item -LiteralPath $executable -Force -ErrorAction SilentlyContinue
        throw 'Checksum do Bicep CLI não confere.'
    }
    return $executable
}

$nodeHome = Get-NodeHome
$javaHome = Get-JavaHome
$bicepPath = Get-BicepPath
$env:JAVA_HOME = $javaHome
$env:MAVEN_USER_HOME = $mavenHome
$env:Path = "$nodeHome;$javaHome\bin;$env:Path"

$frontends = @(
    'frontend',
    'microfrontends/frota',
    'microfrontends/operacoes',
    'microfrontends/painel'
)
foreach ($project in $frontends) {
    Push-Location (Join-Path $projectRoot $project)
    try {
        & (Join-Path $nodeHome 'npm.cmd') ci --no-audit --no-fund
        if ($LASTEXITCODE -ne 0) { throw "Falha ao instalar dependências de $project." }
    } finally {
        Pop-Location
    }
}

Push-Location (Join-Path $projectRoot 'quality')
try {
    & (Join-Path $projectRoot 'services/mvnw.cmd') --batch-mode --no-transfer-progress "-Dmaven.repo.local=$mavenRepository" dependency:go-offline
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao baixar dependências dos testes de contrato.' }
} finally {
    Pop-Location
}

Push-Location (Join-Path $projectRoot 'services')
try {
    & .\mvnw.cmd --batch-mode --no-transfer-progress "-Dmaven.repo.local=$mavenRepository" dependency:go-offline
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao baixar dependências dos serviços Java.' }
} finally {
    Pop-Location
}

Push-Location (Join-Path $projectRoot 'functions/notificar-abastecimento')
try {
    & (Join-Path $projectRoot 'services/mvnw.cmd') --batch-mode --no-transfer-progress "-Dmaven.repo.local=$mavenRepository" dependency:go-offline
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao baixar dependências da Function.' }
} finally {
    Pop-Location
}

if (-not $SkipDockerImages) {
    $docker = Get-Command docker.exe -ErrorAction SilentlyContinue
    if (-not $docker) {
        Write-Warning 'Docker Desktop não está instalado; as imagens serão baixadas na primeira subida.'
    } else {
        & $docker.Source info --format '{{.ServerVersion}}' | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning 'Docker Desktop está instalado, mas o engine não está ativo.'
        } else {
            Push-Location $projectRoot
            try {
                & $docker.Source compose --env-file .env.sprint0.example -f compose.sprint0.yaml pull --ignore-buildable
                if ($LASTEXITCODE -ne 0) { throw 'Falha ao baixar as imagens Docker.' }
            } finally {
                Pop-Location
            }
        }
    }
}

Write-Output "Node.js: $(& (Join-Path $nodeHome 'node.exe') --version)"
Write-Output "Java: $((& (Join-Path $javaHome 'bin/java.exe') --version | Select-Object -First 1).ToString())"
Write-Output "Bicep: $((& $bicepPath --version).ToString())"
Write-Output 'Dependências JavaScript, Maven e Bicep baixadas com sucesso.'
