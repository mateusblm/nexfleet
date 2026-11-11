# ADR 0016 — Retry limitado e DLQ em Indicadores

## Status

Aceita em 05/11/2026 para a quarta fatia da Sprint 2.

## Contexto

O consumidor idempotente suporta duplicatas, mas uma mensagem inválida ou incompatível nunca será corrigida apenas por ser entregue outra vez. Recolocá-la indefinidamente na fila cria um ciclo, ocupa o consumidor e atrasa mensagens válidas.

## Decisão

- O listener tenta processar uma falha no máximo três vezes.
- Os intervalos crescem de 500 ms até o limite de 2 s.
- Depois da terceira falha, a mensagem é rejeitada sem requeue.
- A fila principal declara `x-dead-letter-exchange` e `x-dead-letter-routing-key`.
- O RabbitMQ encaminha a mensagem esgotada para a fila durável `nexfleet.indicadores.projecao-abastecimentos.v1.dlq`.
- A fila principal passa a se chamar `nexfleet.indicadores.projecao-abastecimentos.v1.com-dlq`, pois o RabbitMQ não permite redeclarar uma fila existente com novos argumentos.
- A DLQ não é consumida automaticamente nesta fatia. Ela preserva a mensagem para diagnóstico e reprocessamento controlado futuro.

## Consequências

- Uma mensagem problemática deixa de bloquear continuamente o fluxo normal.
- A falha fica visível e não é descartada silenciosamente.
- Reprocessar uma DLQ exige corrigir a causa antes; devolver a mensagem sem correção recriaria o problema.
- Instalações locais antigas podem manter filas anteriores no volume RabbitMQ. Uma instalação nova cria apenas a topologia atual.
- O registro e o histórico de manutenções continuam fora desta fatia.
