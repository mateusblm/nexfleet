param([int]$Port = 8080)
$ErrorActionPreference = 'Stop'
$response = Invoke-RestMethod -Uri "http://localhost:$Port/api/v1/ambiente" -TimeoutSec 30
if ($response.application -ne 'NexFleet' -or $response.status -ne 'UP') {
    throw 'O ambiente nao esta saudavel.'
}
$expected = @('identidade', 'frota', 'operacoes', 'indicadores')
if ($response.services.Count -ne 4) { throw 'Esperados exatamente quatro servicos.' }
foreach ($name in $expected) {
    $item = @($response.services | Where-Object { $_.name -eq $name })
    if ($item.Count -ne 1 -or $item[0].status -ne 'UP') {
        throw "Servico $name ausente ou indisponivel."
    }
}
Write-Output 'OK: Gateway -> BFF -> quatro servicos -> respectivos bancos.'
