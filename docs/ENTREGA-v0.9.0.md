# NexFleet v0.9.0 — publicação da outbox

## Entregue

- RabbitMQ no Docker Compose local, com volume e painel de administração.
- Migração Flyway V3 para agendamento de novas tentativas.
- Job em lote com `FOR UPDATE SKIP LOCKED`.
- Publicação JSON em exchange e fila duráveis.
- Mensagens persistentes e `publisher confirm`.
- Atualização da outbox somente após confirmação positiva.
- Retry automático sem indisponibilizar a API de Operações.
- Testes unitários do caso de uso e do adaptador RabbitMQ.
- Teste de arquitetura preservando a independência da camada `application`.

## Evidências locais

- 12 testes do serviço Operações passaram em Java 21 no build Docker.
- 11 contêineres ficaram saudáveis.
- Flyway V1, V2 e V3 foram aplicados.
- Evento normal: publicado com uma tentativa e recebido na fila.
- Broker indisponível: evento permaneceu pendente, erro e tentativa foram registrados, e a API continuou `UP`.
- Broker recuperado: retry publicou o evento pendente.
- Reinício do RabbitMQ: mensagens persistentes permaneceram na fila.

## Ainda pendente na Sprint 2

- consumidor idempotente em Indicadores;
- retry com limite e DLQ;
- registro e histórico de manutenções.

A Sprint 2 ainda não está concluída.
