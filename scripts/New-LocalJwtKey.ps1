[CmdletBinding()]
param(
    [string]$Destination = (Join-Path $PSScriptRoot '../.secrets/identidade-jwt.pem')
)

$ErrorActionPreference = 'Stop'
$keyPath = [IO.Path]::GetFullPath($Destination)
if (Test-Path -LiteralPath $keyPath) {
    throw 'A chave RSA já existe e não será substituída, pois isso invalidaria as sessões.'
}

$keyDirectory = [IO.Path]::GetDirectoryName($keyPath)
[IO.Directory]::CreateDirectory($keyDirectory) | Out-Null
$rsa = [Security.Cryptography.RSA]::Create()
$nativePem = $null -ne $rsa.PSObject.Methods['ExportPkcs8PrivateKeyPem']
if ($nativePem) {
    try {
        $rsa.KeySize = 3072
        $pem = $rsa.ExportPkcs8PrivateKeyPem()
        $bytes = [Text.Encoding]::ASCII.GetBytes($pem)
        $stream = [IO.File]::Open(
            $keyPath,
            [IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,
            [IO.FileShare]::None
        )
        try {
            $stream.Write($bytes, 0, $bytes.Length)
        } finally {
            $stream.Dispose()
            [Array]::Clear($bytes, 0, $bytes.Length)
        }
    } finally {
        $rsa.Dispose()
    }
} else {
    $rsa.Dispose()
    & docker info --format '{{.ServerVersion}}' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'Docker Desktop precisa estar ativo para gerar a chave RSA neste PowerShell.'
    }
    & docker run --rm `
        --mount "type=bind,source=$keyDirectory,target=/out" `
        eclipse-temurin:21-jre-jammy `
        sh -c 'umask 077; openssl genpkey -quiet -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out /out/identidade-jwt.pem'
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $keyPath)) {
        throw 'Não foi possível gerar a chave RSA local com Docker.'
    }
}

Write-Output "Chave RSA local criada em $keyPath. Não compartilhe esse arquivo."
