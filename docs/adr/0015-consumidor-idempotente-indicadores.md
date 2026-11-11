# ADR 0015 — Consumidor idempotente em Indicadores

## Status

Aceita em 05/11/2026 para a terceira fatia da Sprint 2.

## Contexto

A entrega pelo broker é pelo menos uma vez. Uma mensagem pode reaparecer após falha de rede, timeout ou queda entre o processamento e o ACK. Somar custos diretamente a cada entrega duplicaria valores no dashboard.

## Decisão

- Indicadores é dono da fila `nexfleet.indicadores.projecao-abastecimentos.v1` e do binding de `operacoes.abastecimento.registrado.v1`.
- Cada evento cria uma projeção local de abastecimento.
- `evento_id` é a chave primária e `abastecimento_id` também é único.
- O adaptador usa `INSERT ... ON CONFLICT DO NOTHING`.
- A transação do listener inclui a verificação implícita de unicidade e a gravação.
- Uma entrega repetida termina com sucesso, sem nova linha e sem novo efeito financeiro.
- Operações considera uma mensagem retornada por falta de rota como falha e mantém a outbox pendente.

## Consequências

- Indicadores pode reconstruir consultas sem acessar o banco de Operações.
- Duplicatas não alteram resultados.
- A projeção é eventualmente consistente: pode ficar temporariamente atrasada quando broker ou consumidor estiverem indisponíveis.
- A ADR 0016 acrescenta retry limitado e DLQ sem alterar a idempotência desta decisão.
