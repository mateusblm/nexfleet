# Evidência CQ03 e CQ04 — consistência e atomicidade

Data da execução de referência: 08/11/2026.

## Ambiente isolado

`Test-Cq03Cq04.ps1` cria um PostgreSQL 18 temporário, publica uma porta aleatória somente em `127.0.0.1`, gera credenciais exclusivas e aplica as cinco migrações Flyway do serviço Operações. Ao terminar, o contêiner é removido inclusive quando um teste falha.

Nenhum banco ou volume ativo do NexFleet é usado, parado ou alterado.

## CQ03 — quilometragem regressiva

Preparação:

- hodômetro do veículo: `1000 km`;
- tentativa de abastecimento: `999 km`;
- Frota simulada como referência válida para que a execução alcance a regra JDBC.

Resultado comprovado por `JdbcAbastecimentosIT.cq03QuilometragemRegressivaRetorna422SemAlterarAsTresTabelas`:

| Verificação | Resultado |
|---|---:|
| Status convertido pelo controller | `422` |
| Linhas novas em `operacoes.abastecimento` | 0 |
| Linhas novas em `operacoes.outbox_evento` | 0 |
| Hodômetro depois da tentativa | `1000 km` |

## CQ04 — rollback integral

O teste acrescenta ao banco efêmero uma restrição temporária que rejeita somente o evento de abastecimento. Dessa forma, a falha acontece depois que o método já tentou inserir o abastecimento e atualizar o hodômetro, exatamente no passo da outbox.

`JdbcAbastecimentosIT.cq04FalhaNaOutboxDesfazAbastecimentoHodometroEEvento` também confirma que `JdbcAbastecimentos` está atrás do proxy transacional do Spring. Depois da exceção:

| Tabela | Linhas persistidas |
|---|---:|
| `operacoes.abastecimento` | 0 |
| `operacoes.hodometro` | 0 |
| `operacoes.outbox_evento` | 0 |

Isso comprova que as três escritas pertencem à mesma transação local.

## Execução

Na raiz do projeto, com Docker Desktop ativo:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-Cq03Cq04.ps1"
```

Para incluir a prova na verificação geral:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-Project.ps1" -SkipInstall -IncludeDatabaseIntegration
```

## Resultado da referência

- PostgreSQL: 18.6, imagem `postgres:18-alpine`;
- migrações aplicadas: V1–V5;
- testes executados: 2;
- falhas: 0;
- tempo dos testes JUnit na verificação geral final: 2,309 s;
- bancos ativos alterados: nenhum.

O workflow de backend também executa o script em um contêiner efêmero, impedindo regressões de CQ03 e CQ04 na CI.
