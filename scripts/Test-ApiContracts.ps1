[CmdletBinding()]
param(
    [string]$BaseUrl = 'http://127.0.0.1:8080'
)

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$envPath = Join-Path $projectRoot '.env.sprint0'

if (-not (Test-Path -LiteralPath $envPath)) {
    throw 'Execute ./scripts/Initialize-Local.ps1 antes do teste integrado.'
}

$settings = @{}
foreach ($line in [IO.File]::ReadAllLines($envPath)) {
    if ([String]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
    $parts = $line.Split('=', 2)
    if ($parts.Count -eq 2) { $settings[$parts[0].Trim()] = $parts[1].Trim() }
}

$email = $settings['LOCAL_USER_EMAIL']
$password = $settings['LOCAL_USER_PASSWORD']
if ([String]::IsNullOrWhiteSpace($email) -or
    [String]::IsNullOrWhiteSpace($password) -or
    $password.StartsWith('SUBSTITUA_')) {
    throw 'Defina LOCAL_USER_EMAIL e LOCAL_USER_PASSWORD em .env.sprint0.'
}

function Invoke-ContractRequest {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Method = 'GET',
        [hashtable]$Headers = @{},
        [object]$Body,
        [int[]]$ExpectedStatus = @(200)
    )

    $correlationId = [guid]::NewGuid().ToString()
    $requestHeaders = @{}
    foreach ($key in $Headers.Keys) { $requestHeaders[$key] = $Headers[$key] }
    $requestHeaders['X-Correlation-ID'] = $correlationId
    $parameters = @{
        Uri = $BaseUrl.TrimEnd('/') + $Path
        Method = $Method
        Headers = $requestHeaders
        UseBasicParsing = $true
        TimeoutSec = 30
    }
    if ($null -ne $Body) {
        $parameters['ContentType'] = 'application/json'
        $parameters['Body'] = $Body | ConvertTo-Json -Depth 10 -Compress
    }

    $response = $null
    try {
        $response = Invoke-WebRequest @parameters
        $status = [int]$response.StatusCode
    } catch {
        $response = $_.Exception.Response
        if ($null -eq $response) { throw }
        $status = [int]$response.StatusCode
    }
    if ($ExpectedStatus -notcontains $status) {
        throw "$Method $Path retornou HTTP $status; esperado: $($ExpectedStatus -join ', ')."
    }

    $returnedCorrelation = [string]$response.Headers['X-Correlation-ID']
    if ($returnedCorrelation -ne $correlationId) {
        throw "$Method $Path não preservou o X-Correlation-ID ponta a ponta."
    }

    $content = $null
    if ($status -ne 204 -and -not [String]::IsNullOrWhiteSpace([string]$response.Content)) {
        $content = $response.Content | ConvertFrom-Json
    }
    return [pscustomobject]@{ Status = $status; Data = $content; Raw = [string]$response.Content }
}

function Assert-Property {
    param([object]$Object, [string]$Name, [string]$Context)
    if ($null -eq $Object -or $Object.PSObject.Properties.Name -notcontains $Name) {
        throw "$Context não retornou o campo obrigatório '$Name'."
    }
}

function Assert-ArrayResponse {
    param([object]$Response, [string]$Context, [string[]]$Fields = @())
    if ($Response.Status -ne 200) { throw "$Context não retornou HTTP 200." }
    foreach ($item in @($Response.Data)) {
        foreach ($field in $Fields) { Assert-Property $item $field $Context }
    }
}

$environment = Invoke-ContractRequest -Path '/api/v1/ambiente'
Assert-Property $environment.Data 'application' 'Ambiente'
Assert-Property $environment.Data 'services' 'Ambiente'
if ($environment.Data.application -ne 'NexFleet' -or $environment.Data.status -ne 'UP') {
    throw 'O ambiente integrado não está saudável.'
}

$login = Invoke-ContractRequest -Path '/api/v1/auth/login' -Method 'POST' -Body @{
    email = $email
    senha = $password
}
Assert-Property $login.Data 'accessToken' 'Login'
Assert-Property $login.Data 'tokenType' 'Login'
Assert-Property $login.Data 'expiresIn' 'Login'
if ($login.Data.tokenType -ne 'Bearer' -or [String]::IsNullOrWhiteSpace($login.Data.accessToken)) {
    throw 'O login retornou um token incompatível com o contrato.'
}
$authorization = @{ Authorization = 'Bearer ' + $login.Data.accessToken }

$session = Invoke-ContractRequest -Path '/api/v1/auth/me' -Headers $authorization
Assert-Property $session.Data 'id' 'Sessão'
Assert-Property $session.Data 'perfil' 'Sessão'
try { [void][guid]::Parse([string]$session.Data.id) } catch { throw 'A sessão não retornou um UUID válido.' }

$expectedUsersStatus = if ($session.Data.perfil -eq 'ADMINISTRADOR') { @(200) } else { @(403) }
$users = Invoke-ContractRequest -Path '/api/v1/usuarios?pagina=0&tamanho=20' `
    -Headers $authorization -ExpectedStatus $expectedUsersStatus
if ($users.Status -eq 200) {
    Assert-ArrayResponse $users 'Usuários' @('id', 'email', 'perfil', 'ativo')
    if ($users.Raw -match 'senha|senhaHash|senha_hash') {
        throw 'A API de usuários expôs um campo relacionado a senha.'
    }
}

$vehicles = Invoke-ContractRequest -Path '/api/v1/veiculos?pagina=0&tamanho=20' -Headers $authorization
Assert-ArrayResponse $vehicles 'Veículos' @('id', 'placa', 'status', 'quilometragem')
$drivers = Invoke-ContractRequest -Path '/api/v1/motoristas?pagina=0&tamanho=20' -Headers $authorization
Assert-ArrayResponse $drivers 'Motoristas' @('id', 'nome', 'cnh', 'status')
$links = Invoke-ContractRequest -Path '/api/v1/vinculos?pagina=0&tamanho=20' -Headers $authorization
Assert-ArrayResponse $links 'Vínculos' @('id', 'veiculoId', 'motoristaId', 'inicio')

$fuel = Invoke-ContractRequest -Path '/api/v1/abastecimentos?pagina=0&tamanho=20' -Headers $authorization
Assert-ArrayResponse $fuel 'Abastecimentos' @('id', 'veiculoId', 'motoristaId', 'valorTotal')
$maintenance = Invoke-ContractRequest -Path '/api/v1/manutencoes?pagina=0&tamanho=20' -Headers $authorization
Assert-ArrayResponse $maintenance 'Manutenções' @('id', 'veiculoId', 'tipo', 'valor')

$dashboard = Invoke-ContractRequest -Path '/api/v1/dashboard' -Headers $authorization
foreach ($field in @(
    'gastoAbastecimentos', 'gastoManutencoes', 'gastoTotal',
    'quantidadeAbastecimentos', 'quantidadeManutencoes', 'totalVeiculos',
    'veiculosDisponiveis', 'veiculosEmUso', 'veiculosEmManutencao',
    'veiculosInativos', 'proximasManutencoes')) {
    Assert-Property $dashboard.Data $field 'Dashboard'
}

Write-Output 'OK: contratos HTTP validados no Gateway com autenticação, dados reais e correlação.'
Write-Output 'OK: Identidade, Frota, Operações e Dashboard responderam pelos caminhos públicos.'
