[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$prometheusUrl = 'http://127.0.0.1:9090'
$expectedTargets = @(
    'gateway:8080',
    'bff:8080',
    'identidade:8080',
    'frota:8080',
    'operacoes:8080',
    'indicadores:8080'
)
$deadline = [DateTime]::UtcNow.AddMinutes(2)
$lastError = $null

do {
    try {
        $response = Invoke-RestMethod -Uri "$prometheusUrl/api/v1/targets" -TimeoutSec 5
        if ($response.status -ne 'success') {
            throw 'A API do Prometheus não retornou sucesso.'
        }

        $targets = @($response.data.activeTargets | Where-Object { $_.labels.job -eq 'nexfleet-java' })
        $missing = @($expectedTargets | Where-Object {
            $target = $_
            -not ($targets | Where-Object {
                $_.labels.instance -eq $target -and $_.health -eq 'up'
            })
        })
        if ($missing.Count -gt 0) {
            throw "Targets ainda indisponíveis: $($missing -join ', ')."
        }

        $query = [Uri]::EscapeDataString('up{job="nexfleet-java"}')
        $metrics = Invoke-RestMethod -Uri "$prometheusUrl/api/v1/query?query=$query" -TimeoutSec 5
        if (@($metrics.data.result).Count -ne $expectedTargets.Count) {
            throw 'A consulta de métricas não retornou os seis serviços Java.'
        }

        Write-Output 'Prometheus coletou métricas dos seis serviços Java.'
        return
    } catch {
        $lastError = $_
        Start-Sleep -Seconds 3
    }
} while ([DateTime]::UtcNow -lt $deadline)

throw "Observabilidade não ficou pronta em dois minutos: $($lastError.Exception.Message)"
