[CmdletBinding()]
param(
    [string]$ProfilePath,
    [ValidateRange(5, 240)][int]$MaxRestoreMinutes = 120,
    [switch]$KeepRestoredServer,
    [switch]$Authorize
)

# CQ10 na homologacao Azure (ADR 0024, repetido na nuvem): restauracao point-in-time do
# PostgreSQL flexivel para um servidor TEMPORARIO na mesma VNet, sem tocar no servidor ativo.
#   1. conta as linhas de todas as tabelas dos cinco bancos no servidor de origem;
#   2. restaura para um ponto posterior a essa contagem e cronometra ate o estado Ready;
#   3. executa verify.sh (17 migracoes e isolamento) e a mesma contagem no servidor restaurado;
#   4. compara as contagens, grava relatorio sem segredos e exclui o servidor temporario.
# RPO = intervalo entre a ultima contagem confirmada e o ponto restaurado.
# RTO = da submissao da restauracao ate a conclusao das verificacoes.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (-not $Authorize) { throw 'Execucao bloqueada: o teste cria um PostgreSQL temporario cobrado. Use -Authorize.' }

$projectRoot = Split-Path -Parent $PSScriptRoot
$azureInfra = Join-Path $projectRoot 'infra/azure'
if ([string]::IsNullOrWhiteSpace($ProfilePath)) { $ProfilePath = Join-Path $azureInfra 'preflight-profile.json' }
$azureProfile = Get-Content -LiteralPath $ProfilePath -Raw -Encoding UTF8 | ConvertFrom-Json
$subscriptionId = [string]$azureProfile.subscriptionId
$resourceGroup = [string]$azureProfile.resourceGroupName
$version = (Get-Content -LiteralPath (Join-Path $projectRoot 'VERSION') -Raw -Encoding UTF8).Trim()
$arm = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers"
$jobUrl = "$arm/Microsoft.App/jobs/job-nexfleet-db-verify"
$services = @('identidade', 'frota', 'operacoes', 'indicadores', 'notificacoes')

function Invoke-AzRetry([string[]]$Arguments, [int]$Attempts = 8) {
    $ErrorActionPreference = 'Continue'
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        $output = & az @Arguments --only-show-errors -o json 2>$null
        if ($LASTEXITCODE -eq 0) {
            if ($output) { return (($output -join "`n") | ConvertFrom-Json) }
            return $null
        }
        Start-Sleep -Seconds (5 * $attempt)
    }
    throw "Falha persistente: az $($Arguments[0..1] -join ' ') ..."
}

$servers = @(Invoke-AzRetry @('postgres', 'flexible-server', 'list', '-g', $resourceGroup, '--subscription', $subscriptionId))
$source = @($servers | Where-Object { $_.name -like 'psql-*' -and $_.name -notlike 'psql-nexfleet-cq10-*' })
if ($source.Count -ne 1) { throw "Esperado um servidor de origem; encontrados $($source.Count)." }
$source = $source[0]
$registry = (@(Invoke-AzRetry @('acr', 'list', '-g', $resourceGroup, '--subscription', $subscriptionId)))[0]
$image = "$($registry.loginServer)/azure-database:$version"

$countScript = @'
set -eu
for svc in identidade frota operacoes indicadores notificacoes; do
  up=$(echo "$svc" | tr a-z A-Z)
  eval "PGUSER=\${${up}_DB_USER}; PGPASSWORD=\${${up}_DB_PASSWORD}"
  export PGUSER PGPASSWORD PGHOST="$DB_HOST" PGSSLMODE=require PGDATABASE="$svc"
  psql --no-password -tA -F ' ' -c "SELECT 'CONTAGEM', '$svc', table_name, (xpath('/row/c/text()', query_to_xml(format('SELECT count(*) AS c FROM %I.%I', table_schema, table_name), false, true, '')))[1]::text FROM information_schema.tables WHERE table_schema = '$svc' AND table_type = 'BASE TABLE' ORDER BY table_name;"
done
echo 'CONTAGEM-FIM'
'@

function New-Environment([string]$DbHost) {
    $variables = @(
        @{ name = 'DB_HOST'; value = $DbHost },
        @{ name = 'DB_SSLMODE'; value = 'require' }
    )
    foreach ($service in $services) {
        $variables += @{ name = "$($service.ToUpper())_DB_USER"; value = "nexfleet_$service" }
        $variables += @{ name = "$($service.ToUpper())_DB_PASSWORD"; secretRef = "$service-db-password" }
    }
    return $variables
}

# Executa o job verify com sobrescrita de comando/host; segredos continuam referenciados no job.
function Start-DatabaseCheck([string]$DbHost, [string[]]$Command) {
    $body = @{ containers = @(@{
        name = 'database'; image = $image; command = $Command
        env = (New-Environment $DbHost); resources = @{ cpu = 0.5; memory = '1Gi' }
    }) } | ConvertTo-Json -Depth 8
    $bodyFile = Join-Path ([IO.Path]::GetTempPath()) "nexfleet-cq10-$([guid]::NewGuid().ToString('N')).json"
    try {
        Set-Content -LiteralPath $bodyFile -Value $body -Encoding UTF8
        $started = Invoke-AzRetry @('rest', '--method', 'post', '--url', "$jobUrl/start?api-version=2024-03-01", '--body', "@$bodyFile")
    } finally { Remove-Item -LiteralPath $bodyFile -Force -ErrorAction SilentlyContinue }
    $name = [string]$started.name
    $limit = (Get-Date).AddMinutes(15)
    while ((Get-Date) -lt $limit) {
        Start-Sleep -Seconds 15
        try { $exec = Invoke-AzRetry @('rest', '--method', 'get', '--url', "$jobUrl/executions/${name}?api-version=2024-03-01") 2 } catch { continue }
        if ($exec.PSObject.Properties['properties'] -and $exec.properties.PSObject.Properties['status']) {
            $status = [string]$exec.properties.status
            if ($status -in @('Succeeded', 'Failed', 'Stopped')) { return [pscustomobject]@{ execution = $name; status = $status } }
        }
    }
    return [pscustomobject]@{ execution = $name; status = 'Timeout' }
}

$workspace = (@(Invoke-AzRetry @('monitor', 'log-analytics', 'workspace', 'list', '-g', $resourceGroup, '--subscription', $subscriptionId)))[0].customerId
function Get-Counts([string]$Execution) {
    $kql = "ContainerAppConsoleLogs_CL | where ContainerGroupName_s startswith '$Execution' | where Log_s startswith 'CONTAGEM' | project Log_s"
    $queryFile = Join-Path ([IO.Path]::GetTempPath()) "nexfleet-cq10-kql-$([guid]::NewGuid().ToString('N')).json"
    Set-Content -LiteralPath $queryFile -Value (@{ query = $kql } | ConvertTo-Json -Compress) -Encoding ASCII
    try {
        for ($attempt = 1; $attempt -le 20; $attempt++) {
            $result = Invoke-AzRetry @('rest', '--method', 'post', '--url', "https://api.loganalytics.io/v1/workspaces/$workspace/query",
                '--resource', 'https://api.loganalytics.io', '--body', "@$queryFile")
            $lines = @($result.tables[0].rows | ForEach-Object { [string]$_[0] })
            if ($lines -contains 'CONTAGEM-FIM') {
                $counts = [ordered]@{}
                foreach ($line in ($lines | Where-Object { $_ -ne 'CONTAGEM-FIM' } | Sort-Object)) {
                    $parts = $line.Trim() -split '\s+'
                    $counts["$($parts[1]).$($parts[2])"] = [long]$parts[3]
                }
                return $counts
            }
            Start-Sleep -Seconds 30
        }
    } finally { Remove-Item -LiteralPath $queryFile -Force -ErrorAction SilentlyContinue }
    throw "Contagens da execucao $Execution nao chegaram ao Log Analytics."
}

Write-Output "Origem: $($source.name). Contando linhas antes do ponto de restauracao..."
$sourceCheck = Start-DatabaseCheck $source.fullyQualifiedDomainName @('/bin/sh', '-c', $countScript)
if ($sourceCheck.status -ne 'Succeeded') { throw "Contagem na origem terminou em $($sourceCheck.status)." }
$countedAt = [DateTime]::UtcNow
$sourceCounts = Get-Counts $sourceCheck.execution
Write-Output "Origem: $($sourceCounts.Count) tabelas contadas ate $($countedAt.ToString('o'))."

# O ponto precisa ser posterior a contagem e anterior ao momento atual.
Start-Sleep -Seconds 90
$restorePoint = [DateTime]::UtcNow.AddSeconds(-30)
$restoredName = "psql-nexfleet-cq10-$($restorePoint.ToString('MMddHHmmss'))"
$restoreStarted = [DateTime]::UtcNow
$restoreBody = @{
    location = $source.location
    properties = @{
        createMode = 'PointInTimeRestore'
        sourceServerResourceId = $source.id
        pointInTimeUTC = $restorePoint.ToString('yyyy-MM-ddTHH:mm:ssZ')
    }
} | ConvertTo-Json -Depth 5
$restoreFile = Join-Path ([IO.Path]::GetTempPath()) "nexfleet-cq10-restore-$([guid]::NewGuid().ToString('N')).json"
Set-Content -LiteralPath $restoreFile -Value $restoreBody -Encoding UTF8
try {
    Invoke-AzRetry @('rest', '--method', 'put', '--url', "$arm/Microsoft.DBforPostgreSQL/flexibleServers/${restoredName}?api-version=2024-08-01", '--body', "@$restoreFile") | Out-Null
} finally { Remove-Item -LiteralPath $restoreFile -Force -ErrorAction SilentlyContinue }
Write-Output "Restauracao PITR submetida: $restoredName, ponto $($restorePoint.ToString('o'))."

$restored = $null
$readyAt = $null
$deadline = $restoreStarted.AddMinutes($MaxRestoreMinutes)
try {
    while ([DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Seconds 30
        try {
            $restored = Invoke-AzRetry @('rest', '--method', 'get', '--url', "$arm/Microsoft.DBforPostgreSQL/flexibleServers/${restoredName}?api-version=2024-08-01") 2
        } catch { continue }
        if ($restored.properties.state -eq 'Ready') { $readyAt = [DateTime]::UtcNow; break }
    }
    if (-not $readyAt) { throw "Servidor restaurado nao ficou Ready em $MaxRestoreMinutes minutos." }
    Write-Output "Servidor restaurado Ready em $([math]::Round(($readyAt - $restoreStarted).TotalMinutes, 1)) min."

    $restoredHost = [string]$restored.properties.fullyQualifiedDomainName
    $verify = Start-DatabaseCheck $restoredHost @('/nexfleet/verify.sh')
    $restoredCheck = Start-DatabaseCheck $restoredHost @('/bin/sh', '-c', $countScript)
    if ($restoredCheck.status -ne 'Succeeded') { throw "Contagem no restaurado terminou em $($restoredCheck.status)." }
    $restoredCounts = Get-Counts $restoredCheck.execution
    $finishedAt = [DateTime]::UtcNow

    $differences = @()
    foreach ($key in $sourceCounts.Keys) {
        $after = if ($restoredCounts.Contains($key)) { $restoredCounts[$key] } else { $null }
        # Linhas gravadas entre a contagem e o ponto podem existir; perda nunca.
        if ($null -eq $after -or $after -lt $sourceCounts[$key]) {
            $differences += "${key}: origem=$($sourceCounts[$key]) restaurado=$after"
        }
    }
    $rpoMinutes = [math]::Round(($restorePoint - $countedAt).TotalMinutes, 1)
    $rtoMinutes = [math]::Round(($finishedAt - $restoreStarted).TotalMinutes, 1)
    $approved = ($verify.status -eq 'Succeeded') -and ($differences.Count -eq 0) -and ($rtoMinutes -le 240)

    $reportPath = Join-Path $azureInfra "cq10-recovery-report-$([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')).json"
    [ordered]@{
        criterion = 'CQ10'
        approved = $approved
        sourceServer = $source.name
        restoredServer = $restoredName
        countedAtUtc = $countedAt.ToString('o')
        restorePointUtc = $restorePoint.ToString('o')
        restoreSubmittedUtc = $restoreStarted.ToString('o')
        readyUtc = $readyAt.ToString('o')
        verifiedUtc = $finishedAt.ToString('o')
        rpoMinutes = $rpoMinutes
        rtoMinutes = $rtoMinutes
        verifySh = $verify.status
        tablesCompared = $sourceCounts.Count
        rowsSource = ($sourceCounts.Values | Measure-Object -Sum).Sum
        rowsRestored = ($restoredCounts.Values | Measure-Object -Sum).Sum
        differences = $differences
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $reportPath -Encoding UTF8

    Write-Output "verify.sh no restaurado: $($verify.status). Tabelas: $($sourceCounts.Count). Divergencias: $($differences.Count)."
    Write-Output "RPO ensaiado: $rpoMinutes min (limite 1440). RTO ensaiado: $rtoMinutes min (limite 240)."
    if (-not $approved) { throw "CQ10 reprovado na Azure. Relatorio: $reportPath" }
    Write-Output "CQ10 APROVADO NA AZURE. Relatorio: $reportPath"
} finally {
    if (-not $KeepRestoredServer) {
        $ErrorActionPreference = 'Continue'
        foreach ($attempt in 1..6) {
            & az rest --method delete --url "$arm/Microsoft.DBforPostgreSQL/flexibleServers/${restoredName}?api-version=2024-08-01" --only-show-errors 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-Output "Servidor temporario $restoredName em exclusao."; break }
            Start-Sleep -Seconds 10
        }
    }
}
