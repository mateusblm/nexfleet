$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$node = Get-ChildItem (Join-Path $projectRoot '.tools') -Directory -Filter 'node-v*-win-x64' -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName 'node.exe') } |
    Sort-Object Name -Descending |
    Select-Object -First 1
$java = Get-ChildItem (Join-Path $projectRoot '.tools/temurin-jdk-21') -Filter java.exe -File -Recurse -ErrorAction SilentlyContinue |
    Select-Object -First 1

if (-not $node -or -not $java) {
    throw 'Execute ./scripts/Install-Dependencies.ps1 antes de ativar o toolchain local.'
}

$env:JAVA_HOME = Split-Path -Parent (Split-Path -Parent $java.FullName)
$env:MAVEN_USER_HOME = Join-Path $projectRoot '.cache/maven-home'
$env:Path = "$($node.FullName);$env:JAVA_HOME\bin;$env:Path"

Write-Output "Node.js local ativo: $(& node.exe --version)"
Write-Output "JDK local ativo: $((& java.exe --version | Select-Object -First 1).ToString())"
