# Aula 22 — testando 100 usuários simultâneos

## O que estamos medindo

Tempo médio pode esconder lentidões. O percentil 95, chamado de p95, indica que 95% das respostas terminaram naquele tempo ou menos. No NexFleet, CQ09 exige `p95 < 2 segundos` para as listas paginadas sob 100 usuários simultâneos.

O teste chama a mesma URL usada pelo navegador. Por isso inclui Gateway, BFF, autorização, serviço e banco. Ele não acessa o PostgreSQL diretamente e não usa respostas mockadas.

## Antes de executar

O backend precisa estar ativo e a conta local deve ter sido provisionada:

```powershell
.\scripts\Start-Local.ps1 -ProvisionUser
```

Nas próximas vezes, basta `Start-Local.ps1` sem `-ProvisionUser`.

## Execução padrão

Na raiz do projeto:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\scripts\Test-Performance.ps1"
```

O padrão cria 100 usuários virtuais, três ciclos por usuário, páginas com 20 itens e limite de 2.000 ms. A saída exibe um JSON com o total e cada endpoint, seguido por `CQ09 aprovado` ou por uma falha explicativa.

## Ajustes úteis

Para um ensaio rápido durante o desenvolvimento:

```powershell
.\scripts\Test-Performance.ps1 -Users 10 -Iterations 1
```

Para testar uma homologação HTTPS:

```powershell
.\scripts\Test-Performance.ps1 `
  -BaseUrl "https://homologacao.exemplo.com" `
  -Users 100 -Iterations 3 -ThresholdMs 2000
```

As credenciais continuam vindo de `.env.sprint0`. Nunca coloque a senha no comando, em documentação ou em captura de tela.

## Entendendo o resultado

- `failures`: deve ser zero;
- `p50Ms`: mediana, ou tempo de metade das respostas;
- `p95Ms`: métrica normativa de CQ09;
- `p99Ms`: mostra a cauda mais lenta;
- `maxMs`: pior chamada isolada, informativa, mas não é o critério definido;
- `throughputRequestsPerSecond`: vazão média observada.

O executor reprova quando o p95 total ou o p95 de qualquer lista chega a 2.000 ms. Isso evita que uma lista lenta fique escondida pela média das demais.

## Automatização

O comando abaixo executa saúde, contratos, EDA, Function, observabilidade e desempenho:

```powershell
.\scripts\Test-E2E.ps1 -IncludePerformance
```

A CI usa esse modo em bancos efêmeros. O resultado local atual está registrado em [Evidência CQ09](../EVIDENCIA-CQ09-DESEMPENHO.md), e a justificativa técnica está na [ADR 0023](../adr/0023-teste-de-desempenho-cq09.md).
