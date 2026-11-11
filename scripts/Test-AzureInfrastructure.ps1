[CmdletBinding()]
param(
    [string]$BicepPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$azureInfra = Join-Path $projectRoot 'infra/azure'
$mainTemplate = Join-Path $azureInfra 'main.bicep'
$platformTemplate = Join-Path $azureInfra 'modules/platform.bicep'
$requirementsPath = Join-Path $azureInfra 'resource-requirements.json'
$planPath = Join-Path $azureInfra 'deployment-plan.example.json'
$whatIfScriptPath = Join-Path $PSScriptRoot 'Invoke-AzureWhatIf.ps1'

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

foreach ($path in @($mainTemplate, $platformTemplate, (Join-Path $azureInfra 'bicepconfig.json'))) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Arquivo Bicep obrigatório ausente: $path"
    }
}
if (-not (Test-Path -LiteralPath $whatIfScriptPath -PathType Leaf)) {
    throw "Executor de what-if ausente: $whatIfScriptPath"
}

$requirements = Read-JsonFile $requirementsPath 'Inventário Azure'
$plan = Read-JsonFile $planPath 'Plano de implantação de exemplo'
if ([int]$requirements.schemaVersion -ne 2) { throw 'O inventário Azure deve usar schemaVersion 2.' }
if ([int]$requirements.expectedResourceCount -ne @($requirements.resources).Count) {
    throw 'expectedResourceCount não corresponde ao número de recursos do inventário.'
}
if ([int]$plan.schemaVersion -ne 1) { throw 'O plano de implantação deve usar schemaVersion 1.' }
if ([bool]$plan.deploymentAuthorized) { throw 'O exemplo nunca pode autorizar implantação.' }
if ([bool]$plan.whatIfAuthorized) { throw 'O exemplo nunca pode autorizar consulta conectada.' }
if ($plan.messagingDecision -ne 'pending') { throw 'O exemplo deve preservar a decisão de mensageria como pending.' }
if ([bool]$plan.safety.containsSecrets) { throw 'O exemplo não pode declarar ou conter segredos.' }
if ([bool]$plan.safety.deployCommandProvided) { throw 'Esta etapa não pode fornecer comando de implantação.' }
if (-not [bool]$plan.safety.requiresConnectedPreflight -or -not [bool]$plan.safety.requiresWhatIfReview) {
    throw 'O plano deve exigir preflight conectado e revisão de what-if.'
}

$bicepFiles = @(Get-ChildItem -LiteralPath $azureInfra -Filter '*.bicep' -File -Recurse)
$allBicep = ($bicepFiles | ForEach-Object {
    Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
}) -join "`n"
if ($allBicep -notmatch '(?m)^param publicationApproved bool = false$') {
    throw 'A trava publicationApproved deve permanecer false por padrão.'
}
if ($allBicep -notmatch '(?m)^param databaseMigrationsCompleted bool = false$' -or
    $allBicep -notmatch '(?m)^var databaseMigrationGate = !workloadsEnabled \|\| databaseMigrationsCompleted$' -or
    $allBicep -notmatch "fail\('workloadsEnabled exige databaseMigrationsCompleted=true") {
    throw 'Os workloads devem permanecer bloqueados ate a conclusao explicita das migracoes.'
}
if ($allBicep -notmatch '(?m)^param jwtPrivateKeyBase64 string$' -or
    $allBicep -notmatch 'jwtPrivateKey:\s*base64ToString\(jwtPrivateKeyBase64\)') {
    throw 'A entrada RSA do template principal deve permanecer segura em Base64 e ser decodificada somente no módulo.'
}
if ($allBicep -notmatch '(?m)^param staticWebLocation string(?: = ''centralus'')?$') {
    throw 'A região separada do Static Web Apps deve permanecer explícita no Bicep.'
}
$platformBicep = Get-Content -LiteralPath $platformTemplate -Raw -Encoding UTF8
if ($platformBicep -notmatch "(?s)resource staticWebApp 'Microsoft\.Web/staticSites@[^']+' = \{.*?location: staticWebLocation") {
    throw 'Static Web Apps deve usar staticWebLocation, não a região principal de dados.'
}
$modeled = 0
$pending = 0
foreach ($item in @($requirements.resources)) {
    $shouldBeModeled = -not ($item.PSObject.Properties.Name -contains 'modeledInBicep') -or [bool]$item.modeledInBicep
    $resourcePattern = [regex]::Escape("$($item.namespace)/$($item.resourceType)@")
    $found = $allBicep -match $resourcePattern
    if ($shouldBeModeled -and -not $found) {
        throw "Tipo obrigatório não encontrado no Bicep: $($item.namespace)/$($item.resourceType)"
    }
    if ($shouldBeModeled) { $modeled++ } else { $pending++ }
}
if ($pending -ne 0) { throw "Nenhuma família pode permanecer pendente no Bicep; encontradas: $pending." }
if ($allBicep -match '(?im)\baz\s+deployment\s+.*\bcreate\b') {
    throw 'Os templates não podem conter comando de implantação.'
}
$whatIfScript = Get-Content -LiteralPath $whatIfScriptPath -Raw -Encoding UTF8
if ($whatIfScript -notmatch '(?m)^\s*-Purpose WhatIf\s*$') {
    throw 'O executor de what-if deve usar o preflight no propósito WhatIf.'
}
if ($whatIfScript -notmatch "'--result-format', 'ResourceIdOnly'" -or
    $whatIfScript -match "'--result-format', 'FullResourcePayloads'") {
    throw 'O what-if deve usar ResourceIdOnly para evitar materializar payloads completos e segredos no relatório.'
}
if ($whatIfScript -notmatch "'--query', '\{status:status,changes:changes\[\]\.\{resourceId:resourceId,changeType:changeType\}\}'") {
    throw 'O what-if deve limitar a saída da CLI a status, resourceId e changeType.'
}
if ($whatIfScript -notmatch '1> \$stdoutFile 2> \$stderrFile' -or
    $whatIfScript -notmatch '\$summaryBytes -gt 5MB') {
    throw 'O what-if deve redirecionar a saída nativa para temporários e limitar o tamanho antes de converter JSON.'
}

if ($whatIfScript -notmatch '''--validation-level'', \$ValidationLevel' -or
    $whatIfScript -notmatch 'ConnectionResetError' -or
    $whatIfScript -notmatch 'MaxTransientRetries') {
    throw 'O what-if deve permitir selecionar a validacao e repetir apenas falhas transitorias dentro de um limite pequeno.'
}
if ($whatIfScript -notmatch "\[ValidateSet\('AzureCli', 'ArmRest'\)\]" -or
    $whatIfScript -notmatch 'api-version=2025-04-01' -or
    $whatIfScript -notmatch "resultFormat = 'ResourceIdOnly'") {
    throw 'O what-if deve oferecer o transporte ARM REST oficial e preservar o relatorio ResourceIdOnly.'
}
if ($whatIfScript -notmatch 'Protect-ArmMessage' -or
    $whatIfScript -notmatch 'status inesperado') {
    throw 'O what-if deve ocultar parametros seguros em erros e aceitar apenas resultado Succeeded.'
}
if ($whatIfScript -notmatch "serviceDatabaseCredentials'\)" -or
    $whatIfScript -notmatch '\$secretValue = \[string\]\$credential\.password' -or
    $whatIfScript -notmatch 'Replace\(\$secretValue, ''<redacted>''\)') {
    throw 'O what-if deve ocultar as credenciais exclusivas dos cinco bancos.'
}

if ([string]::IsNullOrWhiteSpace($BicepPath)) {
    $localBicep = Join-Path $projectRoot '.tools/bicep/bicep.exe'
    $commandBicep = Get-Command bicep -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $localBicep -PathType Leaf) {
        $BicepPath = $localBicep
    } elseif ($commandBicep) {
        $BicepPath = $commandBicep.Source
    }
}
if ([string]::IsNullOrWhiteSpace($BicepPath) -or -not (Test-Path -LiteralPath $BicepPath -PathType Leaf)) {
    throw 'Compilador Bicep não encontrado. Execute Install-Dependencies ou informe -BicepPath.'
}

$temporaryOutput = Join-Path ([System.IO.Path]::GetTempPath()) "nexfleet-main-$([guid]::NewGuid().ToString('N')).json"
try {
    & $BicepPath lint $mainTemplate
    if ($LASTEXITCODE -ne 0) { throw 'O linter Bicep reprovou a infraestrutura Azure.' }
    & $BicepPath build $mainTemplate --outfile $temporaryOutput
    if ($LASTEXITCODE -ne 0) { throw 'A compilação Bicep falhou.' }
    $compiled = Read-JsonFile $temporaryOutput 'Template ARM compilado'
    if ($compiled.contentVersion -ne '1.0.0.0') { throw 'O template ARM compilado possui contentVersion inesperado.' }
} finally {
    Remove-Item -LiteralPath $temporaryOutput -Force -ErrorAction SilentlyContinue
}

Write-Output "Infraestrutura Azure válida: $modeled tipos modelados, $pending pendente e nenhum comando de implantação embutido nos templates."
