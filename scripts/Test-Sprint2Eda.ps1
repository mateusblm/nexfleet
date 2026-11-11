[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$queues = @(
    @{ Main = 'nexfleet.indicadores.projecao-abastecimentos.v1.com-dlq'; Dead = 'nexfleet.indicadores.projecao-abastecimentos.v1.dlq' },
    @{ Main = 'nexfleet.indicadores.projecao-manutencoes.v1.com-dlq'; Dead = 'nexfleet.indicadores.projecao-manutencoes.v1.dlq' },
    @{ Main = 'nexfleet.notificacoes.abastecimentos.v1'; Dead = 'nexfleet.notificacoes.abastecimentos.v1.dlq' }
)

function Get-QueueProblems([object[]]$Output) {
    $problems = @()
    foreach ($item in $queues) {
        $queueLine = $Output | Select-String -SimpleMatch $item.Main | Select-Object -First 1
        if (-not $queueLine) {
            $problems += "A fila esperada nao foi declarada: $($item.Main)"
            continue
        }
        $columns = $queueLine.ToString().Trim() -split '\s+'
        if ($columns.Count -lt 2 -or [int]$columns[-1] -lt 1) {
            $problems += "A fila $($item.Main) nao possui consumidor conectado."
        }
        if (-not ($Output | Select-String -SimpleMatch $item.Dead | Select-Object -First 1)) {
            $problems += "A DLQ esperada nao foi declarada: $($item.Dead)"
        }
    }
    return $problems
}

# Indicadores e a Function conectam alguns segundos depois de o contêiner ficar saudável
# (no CI isso já reprovou um E2E). A exigência é a mesma; só há tempo para conectar.
Push-Location $projectRoot
try {
    $deadline = (Get-Date).AddSeconds(120)
    do {
        $output = & docker compose --env-file .env.sprint0 `
            -f compose.sprint0.yaml `
            exec -T rabbitmq rabbitmqctl list_queues name consumers 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw "Falha ao consultar o RabbitMQ: $output"
        }
        $problems = @(Get-QueueProblems $output)
        if ($problems.Count -eq 0) { break }
        Start-Sleep -Seconds 5
    } while ((Get-Date) -lt $deadline)
    if ($problems.Count -gt 0) {
        throw ($problems -join ' ')
    }
} finally {
    Pop-Location
}

Write-Output 'OK: filas de indicadores e notificacoes possuem consumidores e DLQs declaradas.'
