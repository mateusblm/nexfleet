[CmdletBinding()]
param(
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$image = 'nexfleet-azure-database-migration:test'
$suffix = [guid]::NewGuid().ToString('N').Substring(0, 10)
$network = "nexfleet-migration-test-$suffix"
$container = "nexfleet-pg-test-$suffix"
$adminPassword = $null
$servicePasswords = @{}

function New-TestPassword {
    $bytes = New-Object byte[] 24
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($bytes)
        return [Convert]::ToBase64String($bytes) + '!Aa1'
    } finally {
        $generator.Dispose()
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function Assert-LastExitCode([string]$Message) {
    if ($LASTEXITCODE -ne 0) { throw $Message }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker nao encontrado. Inicie o Docker Desktop antes do teste integrado Azure PostgreSQL.'
}

try {
    if (-not $SkipBuild) {
        Push-Location $projectRoot
        try {
            & docker build --file infra/azure-database/Dockerfile --tag $image .
            Assert-LastExitCode 'Falha ao construir a imagem de migracao Azure.'
        } finally {
            Pop-Location
        }
    }

    $adminPassword = New-TestPassword
    foreach ($name in @('IDENTIDADE', 'FROTA', 'OPERACOES', 'INDICADORES', 'NOTIFICACOES')) {
        $servicePasswords[$name] = New-TestPassword
    }

    & docker network create $network | Out-Null
    Assert-LastExitCode 'Falha ao criar a rede efemera do teste.'

    & docker run -d --name $container --network $network `
        -e POSTGRES_USER=nexfleet_admin `
        -e "POSTGRES_PASSWORD=$adminPassword" `
        -e POSTGRES_DB=postgres `
        postgres:18-alpine | Out-Null
    Assert-LastExitCode 'Falha ao iniciar o PostgreSQL efemero.'

    $ready = $false
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        & docker exec $container pg_isready -U nexfleet_admin -d postgres 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $ready = $true
            break
        }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) { throw 'O PostgreSQL efemero nao ficou pronto.' }

    $services = @('identidade', 'frota', 'operacoes', 'indicadores', 'notificacoes')
    foreach ($service in $services) {
        & docker exec $container psql -v ON_ERROR_STOP=1 -U nexfleet_admin -d postgres `
            -c "CREATE DATABASE $service;" | Out-Null
        Assert-LastExitCode "Falha ao criar o banco efemero $service."
    }

    $migrationArguments = @(
        '--rm', '--network', $network,
        '-e', "DB_HOST=$container",
        '-e', 'DB_SSLMODE=disable',
        '-e', 'POSTGRES_ADMIN_USER=nexfleet_admin',
        '-e', "POSTGRES_ADMIN_PASSWORD=$adminPassword",
        '-e', 'IDENTIDADE_DB_USER=nexfleet_identidade',
        '-e', "IDENTIDADE_DB_PASSWORD=$($servicePasswords.IDENTIDADE)",
        '-e', 'FROTA_DB_USER=nexfleet_frota',
        '-e', "FROTA_DB_PASSWORD=$($servicePasswords.FROTA)",
        '-e', 'OPERACOES_DB_USER=nexfleet_operacoes',
        '-e', "OPERACOES_DB_PASSWORD=$($servicePasswords.OPERACOES)",
        '-e', 'INDICADORES_DB_USER=nexfleet_indicadores',
        '-e', "INDICADORES_DB_PASSWORD=$($servicePasswords.INDICADORES)",
        '-e', 'NOTIFICACOES_DB_USER=nexfleet_notificacoes',
        '-e', "NOTIFICACOES_DB_PASSWORD=$($servicePasswords.NOTIFICACOES)",
        $image
    )

    foreach ($execution in 1..2) {
        Write-Output "Executando bootstrap/migracao idempotente $execution/2..."
        & docker run @migrationArguments
        Assert-LastExitCode "A execucao $execution da migracao falhou."
    }

    $expectedVersions = @{
        identidade = 3
        frota = 4
        operacoes = 5
        indicadores = 3
        notificacoes = 2
    }
    foreach ($service in $services) {
        $count = & docker exec $container psql -U nexfleet_admin -d $service -tA `
            -c "SELECT count(*) FROM $service.flyway_schema_history WHERE success AND version IS NOT NULL;"
        Assert-LastExitCode "Falha ao conferir as migracoes de $service."
        if ([int]$count.Trim() -ne $expectedVersions[$service]) {
            throw "Quantidade inesperada de migracoes em ${service}: $count"
        }
    }

    & docker exec -e "PGPASSWORD=$($servicePasswords.IDENTIDADE)" $container `
        psql -h 127.0.0.1 -U nexfleet_identidade -d identidade -tA -c 'SELECT current_user;' | Out-Null
    Assert-LastExitCode 'O papel identidade nao conectou no proprio banco.'

    $previousErrorPreference = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    & docker exec -e "PGPASSWORD=$($servicePasswords.IDENTIDADE)" $container `
        psql -h 127.0.0.1 -U nexfleet_identidade -d frota -tA -c 'SELECT 1;' 2>$null | Out-Null
    $crossDatabaseExitCode = $LASTEXITCODE
    $ErrorActionPreference = $previousErrorPreference
    if ($crossDatabaseExitCode -eq 0) {
        throw 'Isolamento falhou: o papel identidade conectou no banco frota.'
    }

    # A mesma prova executada na Azure (verify.sh) precisa passar contra o banco efemero.
    $verifyArguments = @('--rm', '--network', $network, '--entrypoint', '/nexfleet/verify.sh') +
        ($migrationArguments | Select-Object -Skip 3)
    & docker run @verifyArguments
    Assert-LastExitCode 'verify.sh reprovou a migracao no banco efemero.'

    # bootstrap-admin.sh: duas execucoes produzem um unico Administrador, sem trocar o hash.
    $testHash = '$2a$12$' + ('a' * 53)
    foreach ($execution in 1..2) {
        & docker run --rm --network $network --entrypoint /nexfleet/bootstrap-admin.sh `
            -e "DB_HOST=$container" -e 'DB_SSLMODE=disable' `
            -e 'IDENTIDADE_DB_USER=nexfleet_identidade' -e "IDENTIDADE_DB_PASSWORD=$($servicePasswords.IDENTIDADE)" `
            -e 'ADMIN_EMAIL=Admin.Teste@Example.com ' -e "ADMIN_PASSWORD_HASH=$testHash" $image | Out-Null
        Assert-LastExitCode "bootstrap-admin.sh falhou na execucao $execution."
    }
    $admins = & docker exec $container psql -U nexfleet_admin -d identidade -tA `
        -c "SELECT count(*) FROM identidade.usuario WHERE email = 'admin.teste@example.com' AND perfil = 'ADMINISTRADOR';"
    if ([int]$admins.Trim() -ne 1) { throw "bootstrap-admin.sh criou $admins administradores; esperado 1." }

    Write-Output 'Migracao Azure aprovada: 17 versoes, repeticao idempotente e isolamento entre bancos.'
} finally {
    & docker rm -f $container 2>$null | Out-Null
    & docker network rm $network 2>$null | Out-Null
    $adminPassword = $null
    foreach ($key in @($servicePasswords.Keys)) { $servicePasswords[$key] = $null }
    $servicePasswords.Clear()
}
