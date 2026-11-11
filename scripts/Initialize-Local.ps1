[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$examplePath = Join-Path $projectRoot '.env.sprint0.example'
$envPath = Join-Path $projectRoot '.env.sprint0'
$keyPath = Join-Path $projectRoot '.secrets/identidade-jwt.pem'

function New-RandomSecret([int]$byteCount) {
    $bytes = New-Object byte[] $byteCount
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $random.GetBytes($bytes)
        return [Convert]::ToBase64String($bytes)
    } finally {
        $random.Dispose()
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function New-RandomUriSecret([int]$byteCount) {
    $bytes = New-Object byte[] $byteCount
    $random = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $random.GetBytes($bytes)
        return ([BitConverter]::ToString($bytes) -replace '-', '').ToLowerInvariant()
    } finally {
        $random.Dispose()
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

$newFile = -not (Test-Path -LiteralPath $envPath)
$content = if ($newFile) {
    [IO.File]::ReadAllText($examplePath, [Text.Encoding]::UTF8)
} else {
    [IO.File]::ReadAllText($envPath, [Text.Encoding]::UTF8)
}
$replacements = @{
    'JWT_SECRET' = New-RandomSecret 32
    'IDENTIDADE_DB_PASSWORD' = New-RandomSecret 24
    'FROTA_DB_PASSWORD' = New-RandomSecret 24
    'OPERACOES_DB_PASSWORD' = New-RandomSecret 24
    'INDICADORES_DB_PASSWORD' = New-RandomSecret 24
    'NOTIFICACOES_DB_PASSWORD' = New-RandomSecret 24
    'RABBITMQ_PASSWORD' = New-RandomUriSecret 24
}
foreach ($item in $replacements.GetEnumerator()) {
    $pattern = '(?m)^' + [Regex]::Escape($item.Key) + '=(.*)$'
    $match = [Regex]::Match($content, $pattern)
    if (-not $match.Success) {
        $content += [Environment]::NewLine + $item.Key + '=' + $item.Value
    } elseif ($match.Groups[1].Value.StartsWith('SUBSTITUA_')) {
        $content = [Regex]::Replace($content, $pattern, $item.Key + '=' + $item.Value)
    }
}
if ($content -notmatch '(?m)^RABBITMQ_USER=') {
    $content += [Environment]::NewLine + 'RABBITMQ_USER=nexfleet'
}
$rabbitUser = [Regex]::Match($content, '(?m)^RABBITMQ_USER=(.*)$').Groups[1].Value.Trim()
$rabbitPassword = [Regex]::Match($content, '(?m)^RABBITMQ_PASSWORD=(.*)$').Groups[1].Value.Trim()
if ($rabbitPassword -notmatch '^[A-Za-z0-9._~-]+$') {
    $rabbitPassword = New-RandomUriSecret 24
    $content = [Regex]::Replace(
        $content, '(?m)^RABBITMQ_PASSWORD=(.*)$', 'RABBITMQ_PASSWORD=' + $rabbitPassword)
    Write-Output 'RABBITMQ_PASSWORD foi rotacionada para um formato seguro em URI.'
}
$rabbitConnection = 'amqp://' + [Uri]::EscapeDataString($rabbitUser) + ':' +
    [Uri]::EscapeDataString($rabbitPassword) + '@rabbitmq:5672'
$connectionPattern = '(?m)^RABBITMQ_CONNECTION=(.*)$'
if ($content -match $connectionPattern) {
    $content = [Regex]::Replace(
        $content, $connectionPattern, 'RABBITMQ_CONNECTION=' + $rabbitConnection)
} else {
    $content += [Environment]::NewLine + 'RABBITMQ_CONNECTION=' + $rabbitConnection
}
[IO.File]::WriteAllText($envPath, $content, (New-Object Text.UTF8Encoding($false)))
if ($newFile) {
    Write-Output '.env.sprint0 criado com segredos locais aleatórios.'
} else {
    Write-Output '.env.sprint0 preservado e complementado com variáveis ausentes.'
}

if (-not (Test-Path -LiteralPath $keyPath)) {
    & (Join-Path $PSScriptRoot 'New-LocalJwtKey.ps1')
} else {
    Write-Output 'A chave RSA local já existe e foi preservada.'
}

Write-Output 'Abra .env.sprint0 e substitua LOCAL_USER_PASSWORD antes de iniciar o ambiente.'
