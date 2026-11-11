[CmdletBinding()]
param(
    [string]$ProfilePath,
    [string]$DeploymentPlanPath,
    [string]$ReportPath,
    [string]$AzPath,
    [ValidateSet('ProviderNoRbac', 'Template')]
    [string]$ValidationLevel = 'ProviderNoRbac',
    [ValidateSet('AzureCli', 'ArmRest')]
    [string]$Transport = 'AzureCli',
    [ValidateRange(0, 3)]
    [int]$MaxTransientRetries = 2
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Net.Http

$projectRoot = Split-Path -Parent $PSScriptRoot
$azureInfra = Join-Path $projectRoot 'infra/azure'
. (Join-Path $PSScriptRoot 'lib/AzureCli.ps1')
if ([string]::IsNullOrWhiteSpace($ProfilePath)) {
    $ProfilePath = Join-Path $azureInfra 'preflight-profile.json'
}
if ([string]::IsNullOrWhiteSpace($DeploymentPlanPath)) {
    $DeploymentPlanPath = Join-Path $azureInfra 'deployment-plan.json'
}
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path $azureInfra "what-if-report-$((Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss')).json"
}

function Read-JsonFile([string]$Path, [string]$Description) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Description não encontrado: $Path"
    }
    try {
        return Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        throw "$Description possui JSON inválido: $Path. $($_.Exception.Message)"
    }
}

function New-TemporaryPassword {
    $bytes = New-Object byte[] 24
    try {
        [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
        return ([Convert]::ToBase64String($bytes) + '!Aa1')
    } finally {
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function Invoke-ArmHttpRequest {
    param(
        [System.Net.Http.HttpClient]$Client,
        [System.Net.Http.HttpMethod]$Method,
        [string]$Uri,
        [string]$Body
    )

    $request = New-Object System.Net.Http.HttpRequestMessage($Method, $Uri)
    if (-not [string]::IsNullOrWhiteSpace($Body)) {
        $request.Content = New-Object System.Net.Http.StringContent($Body, [Text.Encoding]::UTF8, 'application/json')
    }
    try {
        $response = $Client.SendAsync($request).GetAwaiter().GetResult()
        try {
            $responseBody = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $pollUri = $null
            if ($response.Headers.Location) {
                $pollUri = $response.Headers.Location.AbsoluteUri
            } elseif ($response.Headers.Contains('Azure-AsyncOperation')) {
                $pollUri = @($response.Headers.GetValues('Azure-AsyncOperation'))[0]
            }
            $retryAfterSeconds = 5
            if ($response.Headers.RetryAfter -and $response.Headers.RetryAfter.Delta) {
                $retryAfterSeconds = [Math]::Max(2, [Math]::Min(30, [int][Math]::Ceiling($response.Headers.RetryAfter.Delta.TotalSeconds)))
            }
            return [pscustomobject]@{
                StatusCode = [int]$response.StatusCode
                IsSuccess = [bool]$response.IsSuccessStatusCode
                Body = $responseBody
                PollUri = $pollUri
                RetryAfterSeconds = $retryAfterSeconds
            }
        } finally {
            $response.Dispose()
        }
    } finally {
        $request.Dispose()
    }
}

function Protect-ArmMessage {
    param(
        [string]$Message,
        [System.Collections.IDictionary]$DeploymentParameters
    )

    $safeMessage = $Message
    foreach ($name in @('postgresqlAdministratorPassword', 'jwtPrivateKeyBase64')) {
        if ($DeploymentParameters.Contains($name)) {
            $secretValue = [string]$DeploymentParameters[$name].value
            if (-not [string]::IsNullOrWhiteSpace($secretValue)) {
                $safeMessage = $safeMessage.Replace($secretValue, '<redacted>')
            }
        }
    }
    if ($DeploymentParameters.Contains('serviceDatabaseCredentials')) {
        foreach ($credential in $DeploymentParameters['serviceDatabaseCredentials'].value.Values) {
            $secretValue = [string]$credential.password
            if (-not [string]::IsNullOrWhiteSpace($secretValue)) {
                $safeMessage = $safeMessage.Replace($secretValue, '<redacted>')
            }
        }
    }
    return $safeMessage
}

function Invoke-ArmRestWhatIf {
    param(
        [string]$CliPath,
        [string]$TemplatePath,
        [string]$CompiledTemplatePath,
        [System.Collections.IDictionary]$DeploymentParameters,
        [psobject]$AzureProfile,
        [string]$Level,
        [string]$OutputPath
    )

    $token = $null
    $requestJson = $null
    $client = $null
    try {
        $tokenOutput = & $CliPath account get-access-token --resource 'https://management.azure.com/' --query accessToken --output tsv --only-show-errors
        if ($LASTEXITCODE -ne 0) { throw 'Nao foi possivel obter um token ARM pela sessao atual do Azure CLI.' }
        $token = (@($tokenOutput) -join '').Trim()
        if ([string]::IsNullOrWhiteSpace($token)) { throw 'O Azure CLI retornou um token ARM vazio.' }

        & $CliPath bicep build --file $TemplatePath --outfile $CompiledTemplatePath --only-show-errors | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar o Bicep antes do what-if REST.' }
        $compiledTemplate = Get-Content -LiteralPath $CompiledTemplatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        $requestObject = [ordered]@{
            location = [string]$AzureProfile.location
            properties = [ordered]@{
                mode = 'Incremental'
                template = $compiledTemplate
                parameters = $DeploymentParameters
                validationLevel = $Level
                whatIfSettings = @{ resultFormat = 'ResourceIdOnly' }
            }
        }
        $requestJson = $requestObject | ConvertTo-Json -Depth 100 -Compress

        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $client = New-Object System.Net.Http.HttpClient
        $client.Timeout = [TimeSpan]::FromSeconds(120)
        $client.DefaultRequestHeaders.Authorization = New-Object System.Net.Http.Headers.AuthenticationHeaderValue('Bearer', $token)
        [void]$client.DefaultRequestHeaders.UserAgent.ParseAdd('NexFleet-WhatIf/1.0')

        $deploymentName = "nexfleet-$($AzureProfile.environmentName)-what-if"
        $escapedName = [Uri]::EscapeDataString($deploymentName)
        $uri = "https://management.azure.com/subscriptions/$($AzureProfile.subscriptionId)/providers/Microsoft.Resources/deployments/$escapedName/whatIf?api-version=2025-04-01"
        $response = Invoke-ArmHttpRequest -Client $client -Method ([System.Net.Http.HttpMethod]::Post) -Uri $uri -Body $requestJson
        $requestJson = $null
        if (-not $response.IsSuccess) {
            $armError = $response.Body | ConvertFrom-Json -ErrorAction SilentlyContinue
            $message = "HTTP $($response.StatusCode)"
            if ($armError -and $armError.PSObject.Properties.Name -contains 'error' -and
                $armError.error.PSObject.Properties.Name -contains 'message') {
                $message = [string]$armError.error.message
            }
            throw "Azure what-if REST recusado: $(Protect-ArmMessage $message $DeploymentParameters)"
        }

        $deadline = (Get-Date).AddMinutes(15)
        $pollFailures = 0
        while ($response.StatusCode -eq 202) {
            if ([string]::IsNullOrWhiteSpace($response.PollUri)) {
                throw 'Azure aceitou o what-if REST, mas nao retornou a URL de acompanhamento.'
            }
            if ((Get-Date) -ge $deadline) { throw 'O what-if REST excedeu o limite de 15 minutos.' }
            Start-Sleep -Seconds $response.RetryAfterSeconds
            try {
                $response = Invoke-ArmHttpRequest -Client $client -Method ([System.Net.Http.HttpMethod]::Get) -Uri $response.PollUri
                $pollFailures = 0
            } catch {
                $pollFailures++
                if ($pollFailures -gt 5) { throw }
                Write-Warning "Consulta REST interrompida; repetindo o acompanhamento ($pollFailures de 5)."
                Start-Sleep -Seconds 3
            }
        }
        if (-not $response.IsSuccess) {
            $armError = $response.Body | ConvertFrom-Json -ErrorAction SilentlyContinue
            $message = "HTTP $($response.StatusCode)"
            if ($armError -and $armError.PSObject.Properties.Name -contains 'error' -and
                $armError.error.PSObject.Properties.Name -contains 'message') {
                $message = [string]$armError.error.message
            }
            throw "Azure what-if REST falhou: $(Protect-ArmMessage $message $DeploymentParameters)"
        }

        $armResult = $response.Body | ConvertFrom-Json
        if ($armResult.PSObject.Properties.Name -contains 'error' -and $armResult.error) {
            $safeMessage = Protect-ArmMessage ([string]$armResult.error.message) $DeploymentParameters
            throw "Azure what-if REST falhou: $safeMessage"
        }
        $changes = @($armResult.properties.changes)
        $summary = [ordered]@{
            status = [string]$armResult.status
            changes = @($changes | ForEach-Object {
                [ordered]@{ resourceId = [string]$_.resourceId; changeType = [string]$_.changeType }
            })
        }
        $summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    } finally {
        if ($client) { $client.Dispose() }
        $token = $null
        $requestJson = $null
        $requestObject = $null
        $compiledTemplate = $null
    }
}

$profile = Read-JsonFile $ProfilePath 'Perfil Azure real'
$plan = Read-JsonFile $DeploymentPlanPath 'Plano Azure real'
if (-not [bool]$plan.whatIfAuthorized) {
    throw 'What-if bloqueado: marque whatIfAuthorized=true somente depois de revisar o plano local.'
}
if ([bool]$plan.deploymentAuthorized) {
    throw 'deploymentAuthorized deve permanecer false: este script não implanta recursos.'
}
if ($plan.messagingDecision -ne 'servicebus') {
    throw 'What-if bloqueado: messagingDecision deve ser servicebus após decisão explícita da equipe.'
}

& (Join-Path $PSScriptRoot 'Test-AzurePreflight.ps1') `
    -ProfilePath $ProfilePath `
    -AzPath $AzPath `
    -Purpose WhatIf
if ($LASTEXITCODE -ne 0) { throw 'O preflight Azure conectado foi reprovado.' }

$resolvedAzPath = Resolve-AzureCli -AzPath $AzPath

$postgresPassword = [Environment]::GetEnvironmentVariable('NEXFLEET_AZURE_POSTGRES_ADMIN_PASSWORD')
if ([string]::IsNullOrWhiteSpace($postgresPassword) -or $postgresPassword.Length -lt 12) {
    throw 'Defina NEXFLEET_AZURE_POSTGRES_ADMIN_PASSWORD com uma senha forte somente nesta sessão.'
}
$jwtKeyPath = Join-Path $projectRoot '.secrets/identidade-jwt.pem'
if (-not (Test-Path -LiteralPath $jwtKeyPath -PathType Leaf)) {
    throw 'Chave RSA local ausente. Execute Initialize-Local.ps1 antes do what-if.'
}
$jwtPrivateKey = Get-Content -LiteralPath $jwtKeyPath -Raw -Encoding UTF8
if ($jwtPrivateKey -notmatch '-----BEGIN PRIVATE KEY-----') {
    throw 'A chave RSA deve estar no formato PKCS#8 esperado pelo serviço Identidade.'
}
$jwtPrivateKeyBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($jwtPrivateKey))
$jwtPrivateKey = $null
$containerImageTag = (Get-Content -LiteralPath (Join-Path $projectRoot 'VERSION') -Raw).Trim()
$serviceDatabaseCredentials = [ordered]@{
    identidade = [ordered]@{ login = 'nexfleet_identidade'; password = (New-TemporaryPassword) }
    frota = [ordered]@{ login = 'nexfleet_frota'; password = (New-TemporaryPassword) }
    operacoes = [ordered]@{ login = 'nexfleet_operacoes'; password = (New-TemporaryPassword) }
    indicadores = [ordered]@{ login = 'nexfleet_indicadores'; password = (New-TemporaryPassword) }
    notificacoes = [ordered]@{ login = 'nexfleet_notificacoes'; password = (New-TemporaryPassword) }
}

$now = Get-Date
$budgetStart = Get-Date -Year $now.Year -Month $now.Month -Day 1 -Hour 0 -Minute 0 -Second 0
$budgetEnd = $budgetStart.AddYears(1)
$parameterFile = Join-Path ([System.IO.Path]::GetTempPath()) "nexfleet-parameters-$([guid]::NewGuid().ToString('N')).json"
$stdoutFile = Join-Path ([System.IO.Path]::GetTempPath()) "nexfleet-whatif-stdout-$([guid]::NewGuid().ToString('N')).json"
$stderrFile = Join-Path ([System.IO.Path]::GetTempPath()) "nexfleet-whatif-stderr-$([guid]::NewGuid().ToString('N')).txt"
$compiledTemplateFile = Join-Path ([System.IO.Path]::GetTempPath()) "nexfleet-template-$([guid]::NewGuid().ToString('N')).json"
$parameters = [ordered]@{
    '$schema' = 'https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#'
    contentVersion = '1.0.0.0'
    parameters = [ordered]@{
        location = @{ value = [string]$profile.location }
        staticWebLocation = @{ value = [string]$profile.staticWebLocation }
        resourceGroupName = @{ value = [string]$profile.resourceGroupName }
        resourcePrefix = @{ value = [string]$profile.resourcePrefix }
        environmentName = @{ value = [string]$profile.environmentName }
        monthlyBudgetAmount = @{ value = [int][decimal]$profile.monthlyBudgetAmount }
        budgetStartDate = @{ value = $budgetStart.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
        budgetEndDate = @{ value = $budgetEnd.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
        budgetAlertEmails = @{ value = @($profile.budgetAlertEmails) }
        notificationRecipientEmail = @{ value = $(if ($profile.PSObject.Properties.Name -contains 'notificationRecipientEmail') { [string]$profile.notificationRecipientEmail } else { '' }) }
        postgresqlAdministratorLogin = @{ value = 'nexfleetadmin' }
        postgresqlAdministratorPassword = @{ value = $postgresPassword }
        serviceDatabaseCredentials = @{ value = $serviceDatabaseCredentials }
        containerImageTag = @{ value = $containerImageTag }
        jwtPrivateKeyBase64 = @{ value = $jwtPrivateKeyBase64 }
        workloadsEnabled = @{ value = $true }
        databaseMigrationsCompleted = @{ value = $true }
        publicationApproved = @{ value = $true }
    }
}

try {
    if ($Transport -eq 'ArmRest') {
        Invoke-ArmRestWhatIf `
            -CliPath $resolvedAzPath `
            -TemplatePath (Join-Path $azureInfra 'main.bicep') `
            -CompiledTemplatePath $compiledTemplateFile `
            -DeploymentParameters $parameters.parameters `
            -AzureProfile $profile `
            -Level $ValidationLevel `
            -OutputPath $stdoutFile
    } else {
    $parameters | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $parameterFile -Encoding UTF8
    $whatIfArguments = @(
        'deployment', 'sub', 'what-if',
        '--name', "nexfleet-$($profile.environmentName)-what-if",
        '--subscription', [string]$profile.subscriptionId,
        '--location', [string]$profile.location,
        '--template-file', (Join-Path $azureInfra 'main.bicep'),
        '--parameters', "@$parameterFile",
        '--validation-level', $ValidationLevel,
        '--result-format', 'ResourceIdOnly',
        '--query', '{status:status,changes:changes[].{resourceId:resourceId,changeType:changeType}}',
        '--no-pretty-print',
        '--only-show-errors',
        '--output', 'json'
    )
    $whatIfExitCode = 1
    $errorText = ''
    for ($attempt = 0; $attempt -le $MaxTransientRetries; $attempt++) {
        Remove-Item -LiteralPath $stdoutFile, $stderrFile -Force -ErrorAction SilentlyContinue
        $previousErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            & $resolvedAzPath @whatIfArguments 1> $stdoutFile 2> $stderrFile
            $whatIfExitCode = $LASTEXITCODE
        } finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
        if ($whatIfExitCode -eq 0) { break }

        $errorText = if (Test-Path -LiteralPath $stderrFile) {
            Get-Content -LiteralPath $stderrFile -Raw
        } else { 'Azure CLI nao forneceu detalhes.' }
        $transientFailure = $errorText -match '(?i)ConnectionResetError|Connection aborted|timed out|temporarily unavailable'
        if (-not $transientFailure -or $attempt -ge $MaxTransientRetries) { break }

        Write-Warning "A conexao com a Azure foi interrompida. Nova tentativa $($attempt + 2) de $($MaxTransientRetries + 1)."
        Start-Sleep -Seconds 3
    }
    if ($whatIfExitCode -ne 0) {
        $errorText = if (Test-Path -LiteralPath $stderrFile) {
            Get-Content -LiteralPath $stderrFile -Raw
        } else { 'Azure CLI não forneceu detalhes.' }
        $safeError = $errorText -replace '[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}', '<subscription-id>'
        throw "Azure what-if falhou sem criar recursos:`n$safeError"
    }
    }
    if (-not (Test-Path -LiteralPath $stdoutFile -PathType Leaf)) {
        throw 'Azure what-if não produziu o relatório resumido esperado.'
    }
    $summaryBytes = (Get-Item -LiteralPath $stdoutFile).Length
    if ($summaryBytes -gt 5MB) {
        throw "Azure what-if excedeu o limite local de 5 MiB mesmo após o filtro: $summaryBytes bytes."
    }
    $json = Get-Content -LiteralPath $stdoutFile -Raw
    $result = $json | ConvertFrom-Json
    if ([string]$result.status -ne 'Succeeded') {
        throw "Azure what-if terminou com status inesperado: $($result.status)"
    }
    $deletions = @($result.changes | Where-Object { $_.changeType -eq 'Delete' })
    if ($deletions.Count -gt 0) {
        throw "What-if encontrou $($deletions.Count) exclusão(ões). O plano não foi aprovado."
    }
    $json | Set-Content -LiteralPath $ReportPath -Encoding UTF8
} finally {
    $parameters.parameters.postgresqlAdministratorPassword.value = $null
    $parameters.parameters.serviceDatabaseCredentials.value = $null
    $parameters.parameters.jwtPrivateKeyBase64.value = $null
    $postgresPassword = $null
    $jwtPrivateKey = $null
    $jwtPrivateKeyBase64 = $null
    foreach ($credential in $serviceDatabaseCredentials.Values) { $credential.password = $null }
    $serviceDatabaseCredentials = $null
    Remove-Item -LiteralPath $parameterFile, $stdoutFile, $stderrFile, $compiledTemplateFile -Force -ErrorAction SilentlyContinue
}

Write-Output "WHAT-IF CONCLUÍDO. Relatório: $ReportPath"
Write-Output "Transporte: $Transport; validacao: $ValidationLevel"
Write-Output 'Nenhum recurso foi criado, alterado ou excluído.'
