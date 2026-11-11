# ADR 0014 — Publicação da outbox com RabbitMQ

## Status

Aceita em 05/11/2026 para a segunda fatia da Sprint 2.

## Contexto

A v0.8.0 grava `AbastecimentoRegistrado` na mesma transação do abastecimento, mas o evento permanece apenas no PostgreSQL. Publicar diretamente durante a requisição tornaria o registro dependente do broker e poderia causar inconsistência entre banco e mensagem.

## Decisão

- Operações executa um job em lotes após o commit da operação original.
- A consulta usa `FOR UPDATE SKIP LOCKED`, permitindo concorrência entre instâncias sem selecionar a mesma linha simultaneamente.
- A mensagem usa JSON, identificador do evento, tipo, versão, agregado e data em headers.
- Mensagens são persistentes e publicadas em um `TopicExchange` durável.
- `publicado_em` é preenchido somente após `publisher confirm` positivo.
- Falhas mantêm `publicado_em` nulo, incrementam `tentativas`, registram erro e agendam nova tentativa.
- A indisponibilidade do RabbitMQ não altera o readiness da API de Operações.

## Consequências

- O registro de abastecimento continua disponível quando o broker falha.
- A entrega é pelo menos uma vez: uma queda após o broker confirmar e antes do commit pode gerar duplicata.
- Consumidores deverão usar `eventoId` para idempotência.
- Na v0.10.0, a propriedade da fila e do binding foi movida para Indicadores. Operações mantém somente o exchange e trata retorno sem rota como falha para retry.
- DLQ e política de esgotamento de tentativas permanecem para a próxima fatia de EDA.
