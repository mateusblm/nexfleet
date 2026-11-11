[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$queues = @(
    @{ Main = 'nexfleet.indicadores.projecao-abastecimentos.v1.com-dlq'; Dead = 'nexfleet.indicadores.projecao-abastecimentos.v1.dlq' },
    @{ Main = 'nexfleet.indicadores.projecao-manutencoes.v1.com-dlq'; Dead = 'nexfleet.indicadores.projecao-manutencoes.v1.dlq' },
    @{ Main = 'nexfleet.notificacoes.abastecimentos.v1'; Dead = 'nexfleet.notificacoes.abastecimentos.v1.dlq' }
)

Push-Location $projectRoot
try {
    $output = & docker compose --env-file .env.sprint0 `
        -f compose.sprint0.yaml `
        exec -T rabbitmq rabbitmqctl list_queues name consumers 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao consultar o RabbitMQ: $output"
    }

    foreach ($item in $queues) {
        $queueLine = $output | Select-String -SimpleMatch $item.Main | Select-Object -First 1
        if (-not $queueLine) {
            throw "A fila esperada nao foi declarada: $($item.Main)"
        }
        $columns = $queueLine.ToString().Trim() -split '\s+'
        if ($columns.Count -lt 2 -or [int]$columns[-1] -lt 1) {
            throw "A fila $($item.Main) nao possui consumidor conectado."
        }
        if (-not ($output | Select-String -SimpleMatch $item.Dead | Select-Object -First 1)) {
            throw "A DLQ esperada nao foi declarada: $($item.Dead)"
        }
    }
} finally {
    Pop-Location
}

Write-Output 'OK: filas de indicadores e notificacoes possuem consumidores e DLQs declaradas.'
