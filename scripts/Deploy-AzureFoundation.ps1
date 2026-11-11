[CmdletBinding()]
param(
    [string]$ProfilePath,
    [string]$DeploymentPlanPath,
    [string]$SecretsPath,
    [switch]$EnableWorkloads,
    # carga: 1 vCPU e 1-4 replicas somente durante o CQ09; voltar para economico ao terminar.
    [ValidateSet('economico', 'carga')]
    [string]$WorkloadProfile = 'economico',
    [switch]$Authorize
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

if (-not $Authorize) {
    throw 'Implantacao bloqueada. Use -Authorize somente depois da autorizacao explicita de cobranca.'
}

$projectRoot = Split-Path -Parent $PSScriptRoot
$azureInfra = Join-Path $projectRoot 'infra/azure'
if ([string]::IsNullOrWhiteSpace($ProfilePath)) {
    $ProfilePath = Join-Path $azureInfra 'preflight-profile.json'
}
if ([string]::IsNullOrWhiteSpace($DeploymentPlanPath)) {
    $DeploymentPlanPath = Join-Path $azureInfra 'deployment-plan.json'
}
if ([string]::IsNullOrWhiteSpace($SecretsPath)) {
    $SecretsPath = Join-Path $projectRoot '.secrets/azure-homolog-deployment.clixml'
}

foreach ($path in @($ProfilePath, $DeploymentPlanPath, (Join-Path $azureInfra 'main.bicep'))) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Arquivo obrigatorio ausente: $path" }
}

$profile = Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
$plan = Get-Content -LiteralPath $DeploymentPlanPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not [bool]$plan.deploymentAuthorized) { throw 'O plano real ainda nao autoriza deployment.' }
if (-not [bool]$profile.approvals.paidResourcesApproved) { throw 'A cobranca ainda nao foi aprovada no perfil.' }

& (Join-Path $PSScriptRoot 'Test-AzurePreflight.ps1') -ProfilePath $ProfilePath -Purpose Deployment
if ($LASTEXITCODE -ne 0) { throw 'O preflight conectado de deployment falhou.' }

function New-StrongPassword {
    $bytes = New-Object byte[] 30
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($bytes)
        return [Convert]::ToBase64String($bytes) + '!Aa1'
    } finally {
        $generator.Dispose()
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function ConvertFrom-ProtectedValue([Security.SecureString]$Value) {
    return (New-Object System.Net.NetworkCredential('', $Value)).Password
}

if (Test-Path -LiteralPath $SecretsPath -PathType Leaf) {
    $secretBundle = Import-Clixml -LiteralPath $SecretsPath
    if ([int]$secretBundle.schemaVersion -ne 1) { throw 'Bundle de segredos Azure possui versao inesperada.' }
    Write-Output 'Reutilizando bundle de segredos protegido pelo usuario atual do Windows.'
} else {
    $secretDirectory = Split-Path -Parent $SecretsPath
    New-Item -ItemType Directory -Path $secretDirectory -Force | Out-Null
    $serviceCredentials = [ordered]@{}
    foreach ($service in @('identidade', 'frota', 'operacoes', 'indicadores', 'notificacoes')) {
        $serviceCredentials[$service] = [pscustomobject]@{
            login = "nexfleet_$service"
            password = ConvertTo-SecureString (New-StrongPassword) -AsPlainText -Force
        }
    }
    $secretBundle = [pscustomobject]@{
        schemaVersion = 1
        createdUtc = [DateTime]::UtcNow.ToString('o')
        postgresqlAdministratorLogin = 'nexfleetadmin'
        postgresqlAdministratorPassword = ConvertTo-SecureString (New-StrongPassword) -AsPlainText -Force
        services = $serviceCredentials
    }
    $secretBundle | Export-Clixml -LiteralPath $SecretsPath -Depth 8 -Force
    Write-Output "Bundle de segredos criado com protecao DPAPI: $SecretsPath"
}

$jwtKeyPath = Join-Path $projectRoot '.secrets/identidade-jwt.pem'
if (-not (Test-Path -LiteralPath $jwtKeyPath -PathType Leaf)) {
    throw 'Chave JWT ausente. Execute Initialize-Local.ps1 antes do deployment.'
}
$jwtPrivateKeyBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(
    (Get-Content -LiteralPath $jwtKeyPath -Raw -Encoding UTF8)
))

$serviceDatabaseCredentials = [ordered]@{}
foreach ($service in @('identidade', 'frota', 'operacoes', 'indicadores', 'notificacoes')) {
    $credential = $secretBundle.services.$service
    $serviceDatabaseCredentials[$service] = [ordered]@{
        login = [string]$credential.login
        password = ConvertFrom-ProtectedValue $credential.password
    }
}

$notificationRecipientEmail = if ($profile.PSObject.Properties.Name -contains 'notificationRecipientEmail') {
    [string]$profile.notificationRecipientEmail
} else { '' }
if ($notificationRecipientEmail -and -not [bool]$profile.approvals.notificationProviderApproved) {
    throw 'notificationRecipientEmail exige approvals.notificationProviderApproved=true.'
}

$workloadsEnabled = $false
if ($EnableWorkloads) {
    # Os seis Container Apps so sobem depois da prova verify.sh na Azure (ADR 0034).
    $migrationReport = Get-ChildItem -LiteralPath $azureInfra -Filter 'database-migration-report-*.json' |
        Sort-Object Name -Descending | Select-Object -First 1
    if (-not $migrationReport) { throw 'Execute Publish-AzureDatabaseMigration.ps1 antes de habilitar os workloads.' }
    $migration = Get-Content -LiteralPath $migrationReport.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($migration.migrate.status -ne 'Succeeded' -or $migration.verify.status -ne 'Succeeded') {
        throw "O ultimo relatorio de migracao nao foi aprovado: $($migrationReport.Name)"
    }
    $workloadsEnabled = $true
}

$now = Get-Date
$budgetStart = Get-Date -Year $now.Year -Month $now.Month -Day 1 -Hour 0 -Minute 0 -Second 0
$version = (Get-Content -LiteralPath (Join-Path $projectRoot 'VERSION') -Raw -Encoding UTF8).Trim()
$parameters = [ordered]@{
    location = @{ value = [string]$profile.location }
    staticWebLocation = @{ value = [string]$profile.staticWebLocation }
    resourceGroupName = @{ value = [string]$profile.resourceGroupName }
    resourcePrefix = @{ value = [string]$profile.resourcePrefix }
    environmentName = @{ value = [string]$profile.environmentName }
    monthlyBudgetAmount = @{ value = [int][decimal]$profile.monthlyBudgetAmount }
    budgetStartDate = @{ value = $budgetStart.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
    budgetEndDate = @{ value = $budgetStart.AddYears(1).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
    budgetAlertEmails = @{ value = @($profile.budgetAlertEmails) }
    notificationRecipientEmail = @{ value = $notificationRecipientEmail }
    postgresqlAdministratorLogin = @{ value = [string]$secretBundle.postgresqlAdministratorLogin }
    postgresqlAdministratorPassword = @{ value = ConvertFrom-ProtectedValue $secretBundle.postgresqlAdministratorPassword }
    serviceDatabaseCredentials = @{ value = $serviceDatabaseCredentials }
    postgresqlSkuName = @{ value = 'Standard_B1ms' }
    containerImageTag = @{ value = $version }
    jwtPrivateKeyBase64 = @{ value = $jwtPrivateKeyBase64 }
    workloadsEnabled = @{ value = $workloadsEnabled }
    databaseMigrationsCompleted = @{ value = $workloadsEnabled }
    workloadProfile = @{ value = $WorkloadProfile }
    publicationApproved = @{ value = $true }
}
$parameterDocument = [ordered]@{
    '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
    contentVersion = '1.0.0.0'
    parameters = $parameters
}

$parameterFile = Join-Path ([IO.Path]::GetTempPath()) "nexfleet-foundation-$([guid]::NewGuid().ToString('N')).parameters.json"
$reportPath = Join-Path $azureInfra "foundation-deployment-report-$([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')).json"
$deploymentName = "nexfleet-$($profile.environmentName)-foundation"
try {
    $parameterDocument | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $parameterFile -Encoding UTF8
    Write-Output "Iniciando fundacao Azure '$deploymentName' em $($profile.location). Workloads habilitados: $workloadsEnabled."
    # Conexoes longas do Azure CLI sofrem reset (WinError 10054; ADR 0035). A submissao usa
    # --no-wait, e um PUT repetido com o mesmo nome e idempotente; o estado e acompanhado por
    # consultas curtas.
    $subscriptionId = [string]$profile.subscriptionId
    function Get-FoundationDeployment {
        # No Windows PowerShell 5.1, stderr de comando nativo com Stop vira excecao; aqui
        # "nao encontrado" ou reset de conexao sao respostas esperadas.
        $ErrorActionPreference = 'Continue'
        $json = & az deployment sub show --name $deploymentName --subscription $subscriptionId --only-show-errors --output json 2>$null
        if ($LASTEXITCODE -ne 0 -or -not $json) { return $null }
        return ($json | ConvertFrom-Json)
    }
    $submitted = $false
    $ErrorActionPreference = 'Continue'
    # Uma implantacao anterior com o mesmo nome nao pode ser confundida com a atual.
    $submittedAfter = [DateTimeOffset]::UtcNow.AddSeconds(-5)
    function Test-CurrentDeployment($Candidate) {
        if (-not $Candidate) { return $false }
        $state = [string]$Candidate.properties.provisioningState
        if ($state -in @('Accepted', 'Running')) { return $true }
        return ([DateTimeOffset]$Candidate.properties.timestamp) -gt $submittedAfter
    }
    foreach ($attempt in 1..8) {
        & az deployment sub create `
            --name $deploymentName `
            --subscription $subscriptionId `
            --location ([string]$profile.location) `
            --template-file (Join-Path $azureInfra 'main.bicep') `
            --parameters "@$parameterFile" `
            --no-wait `
            --only-show-errors | Out-Null
        if ($LASTEXITCODE -eq 0) { $submitted = $true; break }
        Start-Sleep -Seconds 10
        if (Test-CurrentDeployment (Get-FoundationDeployment)) { $submitted = $true; break }
        Write-Output "Submissao $attempt falhou por erro transitorio; repetindo."
    }
    $ErrorActionPreference = 'Stop'
    if (-not $submitted) { throw 'A submissao da fundacao Azure falhou apos oito tentativas.' }

    $deadline = (Get-Date).AddMinutes(90)
    $deployment = $null
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 30
        $current = Get-FoundationDeployment
        if (-not (Test-CurrentDeployment $current)) { continue }
        $state = [string]$current.properties.provisioningState
        Write-Output "$([DateTime]::UtcNow.ToString('HH:mm:ss'))Z estado: $state"
        if ($state -in @('Succeeded', 'Failed', 'Canceled')) { $deployment = $current; break }
    }
    if (-not $deployment) { throw 'Tempo esgotado acompanhando a fundacao; consulte az deployment sub show.' }
    if ($deployment.properties.provisioningState -eq 'Failed') {
        $failed = & az deployment operation sub list --name $deploymentName --subscription $subscriptionId `
            --query "[?properties.provisioningState=='Failed'].{recurso:properties.targetResource.resourceName,erro:properties.statusMessage.error.message}" `
            --output json 2>$null
        Write-Output $failed
    }
    if ($deployment.properties.provisioningState -ne 'Succeeded') {
        throw "Estado inesperado da fundacao: $($deployment.properties.provisioningState)"
    }
    $safeReport = [ordered]@{
        deploymentName = $deploymentName
        completedUtc = [DateTime]::UtcNow.ToString('o')
        provisioningState = [string]$deployment.properties.provisioningState
        resourceGroupName = [string]$profile.resourceGroupName
        resourceNames = $deployment.properties.outputs.plannedResourceNames.value
        workloadsEnabled = $workloadsEnabled
    }
    $safeReport | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
    Write-Output "FUNDACAO AZURE CONCLUIDA. Relatorio: $reportPath"
} finally {
    Remove-Item -LiteralPath $parameterFile -Force -ErrorAction SilentlyContinue
    $parameters.postgresqlAdministratorPassword.value = $null
    $parameters.serviceDatabaseCredentials.value = $null
    $parameters.jwtPrivateKeyBase64.value = $null
    foreach ($credential in $serviceDatabaseCredentials.Values) { $credential.password = $null }
    $serviceDatabaseCredentials = $null
    $jwtPrivateKeyBase64 = $null
    $parameterDocument = $null
}
