# Entrega v0.12.0 — Manutenções

## Resultado

A Sprint 2 foi concluída localmente com RF12–13, RB05 e RB12–14 refletidos no código. A nova fatia registra e lista manutenções, publica evento pela outbox e projeta o evento idempotentemente em Indicadores.

## Verificação executada em 06/11/2026

- microfrontend Operações: 1 teste e build Vite aprovados;
- build Docker Java 21: Operações 18, Indicadores 12, BFF 50 e Gateway 11 testes aprovados;
- 11 contêineres saudáveis;
- POST público de manutenção retornou sucesso;
- histórico continha o novo registro;
- outbox estava publicada;
- uma projeção foi criada em Indicadores;
- fila de manutenção possuía um consumidor.

## Limites preservados

Não há mudança automática de status, edição/exclusão, dashboard, função serverless ou publicação Azure nesta versão.
