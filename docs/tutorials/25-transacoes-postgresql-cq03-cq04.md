# Aula 25 — consistência e rollback no PostgreSQL

## 1. Por que um mock não basta

Um mock consegue confirmar que um método foi chamado, mas não executa `FOR UPDATE`, constraints nem uma transação PostgreSQL. Para comprovar CQ03 e CQ04 é necessário usar o banco real, mantendo-o separado dos dados do desenvolvedor.

## 2. A transação do abastecimento

`JdbcAbastecimentos.registrar` executa, nesta ordem:

```text
criar/bloquear hodômetro
        ↓
validar quilometragem
        ↓
inserir abastecimento
        ↓
atualizar hodômetro
        ↓
inserir evento na outbox
```

O método possui `@Transactional`. Quando ele é chamado pelo proxy do Spring, todas as instruções usam a mesma transação. Uma exceção não tratada desfaz tudo.

## 3. CQ03: rejeitar antes de escrever

O teste começa com hodômetro em 1000 km e tenta registrar 999 km. A consulta usa `FOR UPDATE`, compara os valores e lança `FalhaAbastecimento` do tipo `INVALIDO`.

O controller converte esse tipo em HTTP `422`. Depois, o teste consulta as três tabelas e confirma que não há abastecimento nem evento novo e que o hodômetro continua em 1000.

## 4. CQ04: falhar depois das primeiras escritas

Para provar rollback, o teste cria uma constraint temporária que recusa um evento `ABASTECIMENTO`. A inserção do abastecimento e a atualização do hodômetro acontecem antes da tentativa da outbox.

Quando a constraint falha, o Spring marca a transação para rollback. As consultas posteriores encontram zero linhas nas três tabelas. A constraint existe somente no banco temporário e é removida junto com o contêiner.

## 5. Como o isolamento funciona

`Test-Cq03Cq04.ps1` usa:

- nome de contêiner aleatório;
- senha gerada em memória;
- porta aleatória em `127.0.0.1`;
- schema criado pelas migrações reais;
- remoção no bloco `finally`, mesmo em caso de erro.

O script não lê `.env.sprint0` e não conhece as senhas dos bancos do NexFleet.

## 6. Executar

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-Cq03Cq04.ps1"
```

Ou com toda a suíte:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-Project.ps1" -SkipInstall -IncludeDatabaseIntegration
```

Consulte a [ADR 0026](../adr/0026-postgresql-efemero-cq03-cq04.md), a [evidência](../EVIDENCIA-CQ03-CQ04-TRANSACAO.md) e a [matriz CQ01–CQ12](../MATRIZ-CQ01-CQ12.md).
