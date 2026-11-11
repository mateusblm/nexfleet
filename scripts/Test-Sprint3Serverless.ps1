[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$envPath = Join-Path $projectRoot '.env.sprint0'
$compose = @('compose', '--env-file', '.env.sprint0', '-f', 'compose.sprint0.yaml')
$mainQueue = 'nexfleet.notificacoes.abastecimentos.v1'
$deadQueue = 'nexfleet.notificacoes.abastecimentos.v1.dlq'

if (-not (Test-Path -LiteralPath $envPath)) {
    throw 'Execute ./scripts/Initialize-Local.ps1 antes deste teste.'
}

$settings = @{}
foreach ($line in [IO.File]::ReadAllLines($envPath)) {
    if ([String]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith('#')) { continue }
    $parts = $line.Split('=', 2)
    if ($parts.Count -eq 2) { $settings[$parts[0].Trim()] = $parts[1].Trim() }
}

$rabbitUser = $settings['RABBITMQ_USER']
$rabbitPassword = $settings['RABBITMQ_PASSWORD']
if ([String]::IsNullOrWhiteSpace($rabbitUser) -or
    [String]::IsNullOrWhiteSpace($rabbitPassword)) {
    throw 'Credenciais RabbitMQ ausentes em .env.sprint0.'
}

$basic = [Convert]::ToBase64String(
    [Text.Encoding]::UTF8.GetBytes($rabbitUser + ':' + $rabbitPassword))
$headers = @{ Authorization = 'Basic ' + $basic }

function Get-Queue([string]$name) {
    $encoded = [Uri]::EscapeDataString($name)
    return Invoke-RestMethod -Uri "http://127.0.0.1:15672/api/queues/%2F/$encoded" `
        -Headers $headers -Method Get
}

function Publish-Event([string]$payload, [guid]$eventId, [guid]$correlationId) {
    $body = @{
        properties = @{
            message_id = $eventId.ToString()
            content_type = 'application/json'
            delivery_mode = 2
            headers = @{
                eventoId = $eventId.ToString()
                eventoTipo = 'AbastecimentoRegistrado'
                eventoVersao = 1
                agregadoTipo = 'ABASTECIMENTO'
                agregadoId = $eventId.ToString()
                ocorridoEm = '2026-11-06T20:00:00Z'
                'X-Correlation-ID' = $correlationId.ToString()
            }
        }
        routing_key = 'operacoes.abastecimento.registrado.v1'
        payload = $payload
        payload_encoding = 'string'
    } | ConvertTo-Json -Depth 5 -Compress
    $result = Invoke-RestMethod `
        -Uri 'http://127.0.0.1:15672/api/exchanges/%2F/nexfleet.eventos/publish' `
        -Headers $headers -ContentType 'application/json' -Method Post -Body $body
    if (-not $result.routed) { throw 'O evento de teste não foi roteado.' }
}

function Get-NotificationCount([guid]$eventId) {
    $existsSql = "SELECT to_regclass('notificacoes.email_capturado') IS NOT NULL;"
    $exists = & docker @compose exec -T notificacoes-db `
        psql -U notificacoes -d notificacoes -tA -c $existsSql
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao consultar as migrações do banco de notificações.' }
    if ($exists.Trim() -ne 't') { return 0 }

    $sql = "SELECT count(*) FROM notificacoes.email_capturado WHERE evento_id='$eventId';"
    $result = & docker @compose exec -T notificacoes-db `
        psql -U notificacoes -d notificacoes -tA -c $sql
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao consultar o banco de notificações.' }
    return [int]$result.Trim()
}

Push-Location $projectRoot
try {
    $main = $null
    for ($attempt = 1; $attempt -le 30; $attempt++) {
        $main = Get-Queue $mainQueue
        if ($main.consumers -ge 1) { break }
        Start-Sleep -Seconds 1
    }
    if ($main.consumers -lt 1) { throw 'A fila de notificação não possui consumidor.' }

    $deadBefore = [int](Get-Queue $deadQueue).messages
    $eventId = [guid]::NewGuid()
    $correlationId = [guid]::NewGuid()
    $payload = [ordered]@{
        eventoId = $eventId
        abastecimentoId = [guid]::NewGuid()
        veiculoId = [guid]::NewGuid()
        motoristaId = [guid]::NewGuid()
        realizadoEm = '2026-11-06T20:00:00Z'
        combustivel = 'DIESEL'
        litros = 45.5
        valorTotal = 320.00
        quilometragem = 1500
        correlationId = $correlationId
    } | ConvertTo-Json -Compress

    Publish-Event $payload $eventId $correlationId
    Publish-Event $payload $eventId $correlationId

    $count = 0
    for ($attempt = 1; $attempt -le 30; $attempt++) {
        $count = Get-NotificationCount $eventId
        if ($count -eq 1) { break }
        Start-Sleep -Seconds 1
    }
    if ($count -ne 1) {
        throw "Idempotência não comprovada: esperado 1 registro, encontrado $count."
    }

    $invalidEventId = [guid]::NewGuid()
    Publish-Event '{"eventoId":' $invalidEventId ([guid]::NewGuid())
    $deadAfter = $deadBefore
    for ($attempt = 1; $attempt -le 30; $attempt++) {
        $deadAfter = [int](Get-Queue $deadQueue).messages
        if ($deadAfter -ge ($deadBefore + 1)) { break }
        Start-Sleep -Seconds 1
    }
    if ($deadAfter -lt ($deadBefore + 1)) {
        throw 'A mensagem inválida não chegou à DLQ no tempo esperado.'
    }

    Write-Output "OK: evento $eventId publicado duas vezes e persistido uma vez."
    Write-Output "OK: mensagem inválida encaminhada à DLQ após tentativas limitadas."
} finally {
    Pop-Location
}
