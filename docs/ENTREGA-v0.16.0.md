# Entrega v0.16.0 — correlação e logs rastreáveis

## Resultado

A segunda fatia da Sprint 4 acrescenta rastreabilidade ponta a ponta. Uma chamada recebe um UUID no Gateway, preserva esse valor no BFF e nos microsserviços e, quando gera evento, continua identificável pela outbox, RabbitMQ, Indicadores e Azure Function.

## Componentes entregues

- validação e geração de `X-Correlation-ID` no Gateway;
- resposta com um único cabeçalho de correlação;
- filtros HTTP e MDC nos seis serviços Java;
- propagação automática pelos clientes `RestClient` do BFF e de Operações;
- formato de log com serviço, correlação, método, caminho, status e duração;
- migração Flyway V5 com `correlation_id UUID NOT NULL` na outbox;
- `correlationId` aditivo no payload e cabeçalho RabbitMQ;
- consumo correlacionado em Indicadores e na Function;
- fallback para eventos antigos por `messageId` ou `eventoId`;
- testes contra valor inválido, duplicação do cabeçalho, propagação HTTP, cabeçalho RabbitMQ e compatibilidade da Function.

## Segurança

O identificador é aceito somente quando é UUID. Os novos logs não registram query string, corpo, JWT, senha, CPF, CNH ou campos de negócio. Correlação é metadado de diagnóstico e não substitui autenticação ou autorização.

## Verificação

- 172 testes dos seis serviços Java aprovados;
- 8 testes da Azure Function aprovados;
- imagens Docker reconstruídas com os testes internos aprovados;
- Compose completo saudável e dados dos volumes preservados;
- Flyway V5 aplicada com sucesso no PostgreSQL de Operações;
- um mesmo UUID observado em Gateway, BFF, Identidade, Frota, Operações e Indicadores;
- resposta HTTP 200 com exatamente um `X-Correlation-ID`.

Os 43 testes frontend e quatro builds Vite permanecem válidos porque esta fatia não alterou os contratos de tela. A Sprint 4 continua em andamento: faltam evidências formais de desempenho e recuperação, contratos/E2E restantes, revisão final dos diagramas e publicação Azure aprovada.
