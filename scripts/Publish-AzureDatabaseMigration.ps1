[CmdletBinding()]
param(
    [string]$ProfilePath,
    [string]$SecretsPath,
    [switch]$SkipPush,
    # Provisiona o primeiro Administrador (bootstrap-admin.sh). A senha e gerada uma unica vez e
    # guardada com DPAPI em .secrets/azure-homolog-admin.clixml; so o hash BCrypt chega a Azure.
    [string]$AdministratorEmail,
    [switch]$Authorize
)

# Etapa 4 da publicacao: publica a imagem infra/azure-database no ACR, cria os jobs
# migrate/verify (infra/azure/migration-job.bicep) dentro da VNet, executa os dois e grava
# um relatorio sem segredos. Requer a fundacao concluida (Deploy-AzureFoundation.ps1).

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $Authorize) {
    throw 'Execucao bloqueada. Use -Authorize somente depois da fundacao Azure concluida.'
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$azureInfra = Join-Path $projectRoot 'infra/azure'
if ([string]::IsNullOrWhiteSpace($ProfilePath)) { $ProfilePath = Join-Path $azureInfra 'preflight-profile.json' }
if ([string]::IsNullOrWhiteSpace($SecretsPath)) {
    $SecretsPath = Join-Path $projectRoot '.secrets/azure-homolog-deployment.clixml'
}
if (-not (Test-Path -LiteralPath $SecretsPath -PathType Leaf)) {
    throw 'Bundle de segredos ausente. Execute Deploy-AzureFoundation.ps1 antes.'
}

$azureProfile = Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
$subscriptionId = [string]$azureProfile.subscriptionId
$resourceGroup = [string]$azureProfile.resourceGroupName
$version = (Get-Content -LiteralPath (Join-Path $projectRoot 'VERSION') -Raw -Encoding UTF8).Trim()
$jobApiVersion = '2024-03-01'

# Conexoes com o ARM sofrem reset intermitente (ADR 0035): toda chamada curta e repetida.
function Invoke-AzRetry([string[]]$Arguments, [int]$Attempts = 6) {
    $ErrorActionPreference = 'Continue'
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        $output = & az @Arguments --subscription $subscriptionId --only-show-errors --output json 2>$null
        if ($LASTEXITCODE -eq 0) {
            if ($output) { return (($output -join "`n") | ConvertFrom-Json) }
            return $null
        }
        Start-Sleep -Seconds (5 * $attempt)
    }
    throw "Falha persistente no Azure CLI: az $($Arguments[0..2] -join ' ') ..."
}

function Get-SingleResource([string]$Type, [string]$NamePrefix) {
    $items = @(Invoke-AzRetry @('resource', 'list', '--resource-group', $resourceGroup, '--resource-type', $Type))
    $match = @($items | Where-Object { $_.name.StartsWith($NamePrefix) })
    if ($match.Count -ne 1) { throw "Esperado um recurso $Type com prefixo $NamePrefix; encontrados $($match.Count)." }
    return $match[0]
}

$registry = Get-SingleResource 'Microsoft.ContainerRegistry/registries' 'cr'
$environment = Get-SingleResource 'Microsoft.App/managedEnvironments' 'cae-'
$postgres = Get-SingleResource 'Microsoft.DBforPostgreSQL/flexibleServers' 'psql-'
$identity = Get-SingleResource 'Microsoft.ManagedIdentity/userAssignedIdentities' 'id-identidade-'
$registryServer = "$($registry.name).azurecr.io"
$postgresHost = "$($postgres.name).postgres.database.azure.com"
$image = "$registryServer/azure-database:$version"

if (-not $SkipPush) {
    $localImage = "nexfleet/azure-database:$version"
    & docker image inspect $localImage *> $null
    if ($LASTEXITCODE -ne 0) {
        Push-Location $projectRoot
        try { & docker build --file infra/azure-database/Dockerfile --tag $localImage . } finally { Pop-Location }
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao construir a imagem de migracao.' }
    }
    $ErrorActionPreference = 'Continue'
    $loggedIn = $false
    foreach ($attempt in 1..6) {
        & az acr login --name $registry.name --subscription $subscriptionId --only-show-errors 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) { $loggedIn = $true; break }
        Start-Sleep -Seconds (5 * $attempt)
    }
    if (-not $loggedIn) { throw 'Falha no login do ACR por Microsoft Entra ID.' }
    & docker tag $localImage $image
    $pushed = $false
    foreach ($attempt in 1..5) {
        & docker push $image
        if ($LASTEXITCODE -eq 0) { $pushed = $true; break }
        Start-Sleep -Seconds (10 * $attempt)
    }
    $ErrorActionPreference = 'Stop'
    if (-not $pushed) { throw "Falha ao publicar $image." }
}

function ConvertFrom-ProtectedValue([Security.SecureString]$Value) {
    return (New-Object System.Net.NetworkCredential('', $Value)).Password
}

$administratorHash = ''
if (-not [string]::IsNullOrWhiteSpace($AdministratorEmail)) {
    $AdministratorEmail = $AdministratorEmail.Trim().ToLowerInvariant()
    if ($AdministratorEmail -notmatch '^[^\s@]+@[^\s@]+\.[^\s@]+$') { throw 'AdministratorEmail invalido.' }
    $adminSecretsPath = Join-Path (Split-Path -Parent $SecretsPath) 'azure-homolog-admin.clixml'
    if (Test-Path -LiteralPath $adminSecretsPath -PathType Leaf) {
        $adminSecret = Import-Clixml -LiteralPath $adminSecretsPath
    } else {
        $bytes = New-Object byte[] 18
        [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
        $generated = ([Convert]::ToBase64String($bytes) -replace '[+/=]', 'x') + '!Aa1'
        $adminSecret = [pscustomobject]@{
            email = $AdministratorEmail
            password = ConvertTo-SecureString $generated -AsPlainText -Force
        }
        $adminSecret | Export-Clixml -LiteralPath $adminSecretsPath -Force
        $generated = $null
        Write-Output "Senha do Administrador criada com protecao DPAPI: $adminSecretsPath"
    }
    if ($adminSecret.email -ne $AdministratorEmail) { throw "O bundle do Administrador pertence a $($adminSecret.email)." }
    # Hash BCrypt custo 12, igual ao BCryptPasswordEncoder(12) do servico Identidade.
    $env:NX_ADMIN_PASSWORD = ConvertFrom-ProtectedValue $adminSecret.password
    # PowerShell 5.1: stderr do docker (pull, avisos) nao pode virar excecao com Stop.
    $ErrorActionPreference = 'Continue'
    try {
        & docker pull --quiet python:3.13-slim 2>$null | Out-Null
        # O codigo Python vai por variavel de ambiente: o PowerShell 5.1 corrompe aspas
        # aninhadas em argumentos de comandos nativos.
        $env:NX_PY = "import bcrypt,os;print(bcrypt.hashpw(os.environ['NX_ADMIN_PASSWORD'].encode(),bcrypt.gensalt(12)).decode())"
        $administratorHash = (& docker run --rm -e NX_ADMIN_PASSWORD -e NX_PY python:3.13-slim sh -c `
            'set -f; pip install --quiet --disable-pip-version-check --root-user-action=ignore bcrypt==4.2.1 >/dev/null 2>&1 && echo $NX_PY | python -' 2>$null |
            Select-Object -Last 1)
        $env:NX_PY = $null
    } finally {
        $env:NX_ADMIN_PASSWORD = $null
        $ErrorActionPreference = 'Stop'
    }
    $administratorHash = "$administratorHash".Trim()
    if ($administratorHash -notmatch '^\$2[aby]\$12\$[./A-Za-z0-9]{53}$') { throw 'Falha ao gerar o hash BCrypt do Administrador.' }
}

$secretBundle = Import-Clixml -LiteralPath $SecretsPath
$credentials = [ordered]@{}
foreach ($service in @('identidade', 'frota', 'operacoes', 'indicadores', 'notificacoes')) {
    $credentials[$service] = [ordered]@{
        login = [string]$secretBundle.services.$service.login
        password = ConvertFrom-ProtectedValue $secretBundle.services.$service.password
    }
}
$parameters = [ordered]@{
    location = @{ value = [string]$azureProfile.location }
    tags = @{ value = @{ application = 'NexFleet'; environment = [string]$azureProfile.environmentName; managedBy = 'Bicep'; costCenter = 'PJBL' } }
    environmentId = @{ value = [string]$environment.id }
    image = @{ value = $image }
    registryServer = @{ value = $registryServer }
    registryIdentityId = @{ value = [string]$identity.id }
    postgresqlHost = @{ value = $postgresHost }
    postgresqlAdministratorLogin = @{ value = [string]$secretBundle.postgresqlAdministratorLogin }
    postgresqlAdministratorPassword = @{ value = ConvertFrom-ProtectedValue $secretBundle.postgresqlAdministratorPassword }
    serviceDatabaseCredentials = @{ value = $credentials }
    administratorEmail = @{ value = [string]$AdministratorEmail }
    # [string]: saida de comando nativo vem embrulhada em PSObject e viraria objeto no JSON.
    administratorPasswordHash = @{ value = [string]$administratorHash }
}
$parameterFile = Join-Path ([IO.Path]::GetTempPath()) "nexfleet-migration-$([guid]::NewGuid().ToString('N')).parameters.json"
$deploymentName = 'nexfleet-database-jobs'
try {
    [ordered]@{
        '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
        contentVersion = '1.0.0.0'
        parameters = $parameters
    } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $parameterFile -Encoding UTF8

    $ErrorActionPreference = 'Continue'
    $submitted = $false
    $lastError = ''
    foreach ($attempt in 1..6) {
        $errorFile = [IO.Path]::GetTempFileName()
        & az deployment group create --name $deploymentName --resource-group $resourceGroup `
            --subscription $subscriptionId --template-file (Join-Path $azureInfra 'migration-job.bicep') `
            --parameters "@$parameterFile" --no-wait --only-show-errors 2>$errorFile | Out-Null
        $exitCode = $LASTEXITCODE
        # Mensagens de erro do ARM nao ecoam valores de parametros seguros.
        $lastError = (Get-Content -LiteralPath $errorFile -Raw -ErrorAction SilentlyContinue)
        Remove-Item -LiteralPath $errorFile -Force -ErrorAction SilentlyContinue
        if ($exitCode -eq 0) { $submitted = $true; break }
        if ($lastError -notmatch '10054|Connection aborted|timed out|ConnectionError') { break }
        Start-Sleep -Seconds (5 * $attempt)
    }
    $ErrorActionPreference = 'Stop'
    if (-not $submitted) { throw "Falha ao submeter os jobs de banco: $lastError" }
} finally {
    Remove-Item -LiteralPath $parameterFile -Force -ErrorAction SilentlyContinue
    $parameters.postgresqlAdministratorPassword.value = $null
    foreach ($credential in $credentials.Values) { $credential.password = $null }
    $parameters = $null
}

$deadline = (Get-Date).AddMinutes(20)
$state = ''
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 15
    try {
        $deployment = Invoke-AzRetry @('deployment', 'group', 'show', '--name', $deploymentName, '--resource-group', $resourceGroup) 2
        $state = [string]$deployment.properties.provisioningState
    } catch { continue }
    Write-Output "Jobs: $state"
    if ($state -in @('Succeeded', 'Failed', 'Canceled')) { break }
}
if ($state -ne 'Succeeded') { throw "Criacao dos jobs terminou em '$state'." }

function Invoke-Job([string]$JobName) {
    $jobUrl = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.App/jobs/$JobName"
    $started = Invoke-AzRetry @('rest', '--method', 'post', '--url', "$jobUrl/start?api-version=$jobApiVersion")
    $executionName = [string]$started.name
    # Write-Host: progresso nao pode entrar no valor de retorno da funcao.
    Write-Host "Execucao iniciada: $JobName/$executionName"
    $limit = (Get-Date).AddMinutes(30)
    while ((Get-Date) -lt $limit) {
        Start-Sleep -Seconds 20
        try {
            $execution = Invoke-AzRetry @('rest', '--method', 'get', '--url', "$jobUrl/executions/${executionName}?api-version=$jobApiVersion") 2
        } catch { continue }
        # Logo apos o start a execucao pode vir sem properties.status (StrictMode).
        $status = ''
        if ($execution -and $execution.PSObject.Properties['properties'] -and
            $execution.properties.PSObject.Properties['status']) {
            $status = [string]$execution.properties.status
        }
        if (-not $status) { continue }
        Write-Host "  ${JobName}: $status"
        if ($status -in @('Succeeded', 'Failed', 'Stopped', 'Degraded')) {
            return [pscustomobject]@{ job = $JobName; execution = $executionName; status = $status }
        }
    }
    return [pscustomobject]@{ job = $JobName; execution = $executionName; status = 'Timeout' }
}

$migrate = Invoke-Job 'job-nexfleet-db-migrate'
if ($migrate.status -ne 'Succeeded') {
    throw "Migracao terminou em '$($migrate.status)'. Consulte os logs: ContainerAppConsoleLogs_CL, execucao $($migrate.execution)."
}
$verify = Invoke-Job 'job-nexfleet-db-verify'
$administrator = $null
if ($administratorHash) {
    $administrator = Invoke-Job 'job-nexfleet-db-admin'
    if ($administrator.status -ne 'Succeeded') { throw "Bootstrap do Administrador terminou em '$($administrator.status)'." }
}

$reportPath = Join-Path $azureInfra "database-migration-report-$([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')).json"
[ordered]@{
    completedUtc = [DateTime]::UtcNow.ToString('o')
    image = $image
    postgresql = $postgres.name
    migrate = $migrate
    verify = $verify
    administratorBootstrap = $administrator
    expectedMigrations = 17
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $reportPath -Encoding UTF8

if ($verify.status -ne 'Succeeded') {
    throw "Verificacao de versoes/isolamento terminou em '$($verify.status)'. Relatorio: $reportPath"
}
Write-Output "MIGRACOES AZURE CONCLUIDAS: 17 versoes e isolamento comprovados. Relatorio: $reportPath"
Write-Output 'Proximo passo: implantar com databaseMigrationsCompleted=true e workloadsEnabled=true.'
