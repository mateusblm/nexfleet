# NexFleet v0.8.0 — primeira fatia da Sprint 2

## Entregue

- Microfrontend real para registrar e consultar abastecimentos.
- Rotas explícitas no Gateway e BFF.
- Validação RSA/JWKS em Operações.
- Contrato público de Frota para validar veículo, motorista, CNH e vínculo na data.
- Flyway V2 com abastecimento, hodômetro e outbox.
- Transação única com bloqueio do hodômetro e evento `AbastecimentoRegistrado` v1.
- ADR 0013, Aula 12 e testes de domínio, contrato e arquitetura.

## Verificação local

- Frontend: 1 teste e build Vite aprovados.
- Backend alterado: Frota 28, Operações 9, BFF 48 e Gateway 10 testes aprovados no build das imagens.
- Flyway V1–V2 aplicado em PostgreSQL 18.
- Fluxo público: criação confirmada, hodômetro 1500, uma linha de abastecimento, uma linha de outbox e tentativa de 1400 recusada com `422`.
- Dados temporários do teste foram removidos.

## Ainda falta na Sprint 2

- Publicar a outbox no broker.
- Retry, confirmação, DLQ e idempotência dos consumidores.
- Manutenções e suas regras pendentes.
- Política de correção/cancelamento de operações.

Não tratar esta versão como conclusão da Sprint 2.
