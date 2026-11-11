# ADR 0013 — Abastecimento, hodômetro e outbox transacional

## Status

Aceita em 05/11/2026 para a primeira fatia da Sprint 2.

## Contexto

RF09–11 e RB08–11 exigem abastecimento completo, valores positivos, histórico por veículo e hodômetro não regressivo. A arquitetura também determina que Operações seja a fonte da verdade do hodômetro e que o evento seja salvo sem depender da disponibilidade do broker.

## Decisão

1. Litros e valor total usam `NUMERIC(12,2)` e aceitam no máximo duas casas decimais.
2. O comando exige veículo não inativo, motorista ativo, CNH válida e vínculo que cubra a data informada. Operações consulta um contrato público de Frota; não lê o banco de Frota.
3. O hodômetro é bloqueado por veículo durante a transação. Quilometragem menor que a atual retorna `422` e toda a transação é revertida.
4. Abastecimento, novo hodômetro e evento `AbastecimentoRegistrado` v1 são gravados na mesma transação PostgreSQL.
5. Registros são imutáveis nesta fatia. Edição, cancelamento e correção continuam fora do escopo até a política de auditoria ser aprovada.
6. O instante pode ser atual ou passado, mas nunca futuro. Um lançamento passado não pode reduzir o hodômetro atual.

## Consequências

- Concorrência de dois lançamentos do mesmo veículo é serializada pelo bloqueio do hodômetro.
- O retorno `201` confirma somente a transação de Operações; publicação no broker será adicionada na próxima fatia.
- O evento permanece na outbox se o broker estiver indisponível.
- A validação remota pode falhar com `503`; nesse caso nada é gravado.
- Não existem chaves estrangeiras entre os bancos dos microsserviços.

## Rollback

A migração V2 é aditiva. Reverter a aplicação para v0.7.0 deixa as novas tabelas sem leitores, preservando dados. Remover tabelas ou dados exige uma migração destrutiva separada e autorização explícita.
