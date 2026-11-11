# NexFleet v0.10.0 — consumidor idempotente

## Entregue

- Consumidor RabbitMQ no serviço Indicadores.
- Fila e binding pertencentes ao consumidor.
- Migração Flyway V2 de Indicadores.
- Projeção PostgreSQL de abastecimentos.
- Idempotência por `evento_id` e `abastecimento_id` únicos.
- Proteção contra publicação sem fila vinculada em Operações.
- Testes unitários, de arquitetura e integração real.
- Verificação de consumidor conectado no script de inicialização.

## Evidências locais

- Flyway V1 e V2 aplicados em Indicadores.
- Duas cópias do mesmo evento foram roteadas.
- A fila foi consumida e apenas uma projeção foi criada.
- Fluxo outbox → RabbitMQ → Indicadores criou uma projeção e marcou a outbox com uma tentativa.
- A fila terminou vazia com um consumidor conectado.

## Ainda pendente na Sprint 2

- retry limitado e DLQ;
- registro e histórico de manutenções.

A Sprint 2 ainda não está concluída.
