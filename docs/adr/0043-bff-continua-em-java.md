# ADR 0043 — BFF continua em Java/Spring Boot

Data: 11/11/2026
Estado: aceita

## Contexto

Para o BFF, o Node.js foi considerado como alternativa de linguagem. O BFF do NexFleet existe desde a Sprint 0 em Java 21 e Spring Boot, como os demais serviços (ADR 0001). Ele já:

- valida o JWT RSA pela chave pública JWKS da Identidade (ADR 0007);
- propaga o `X-Correlation-ID` (ADR 0021);
- compõe o dashboard (ADR 0018) e orquestra a exclusão definitiva (ADR 0038);
- é protegido por testes MockMvc e regras ArchUnit, como os outros serviços.

A v1.0.0 ainda precisava acrescentar `GET /aggregated-data` (ADR 0041). Reescrever o BFF caberia no mesmo prazo das migrações de banco, da separação em repositórios e da publicação.

## Decisão

O BFF continua em **Java 21 + Spring Boot**, no repositório `nexfleet-bff`, com a mesma organização em Vertical Slice + Clean Architecture dos demais serviços. A nova rota `GET /aggregated-data` foi implementada como a fatia `consultaragregado`, com threads virtuais para as chamadas concorrentes. A reescrita em Node.js ficou explicitamente fora do escopo da v1.0.0.

## Consequências

- O requisito funcional do BFF (rota de agregação combinando dois microsserviços e uma Function HTTP) é atendido sem trocar de linguagem.
- Nenhum teste, regra de segurança ou contrato do BFF precisou ser refeito; o contrato `contracts/*.openapi.yaml` e o `quality/` continuam valendo.
- O time mantém uma única pilha no backend (Java, Maven, ArchUnit, mesmo Dockerfile e mesmo CI).

## Alternativas rejeitadas

- **Reescrever o BFF em Node.js (NestJS ou Express):** refaria validação JWT, correlação, composição do dashboard, exclusão definitiva e todos os testes, sem ganho funcional, com risco para a entrega.
- **Um segundo BFF em Node.js só para `/aggregated-data`:** duplicaria autenticação e configuração e acrescentaria mais um Container App.
