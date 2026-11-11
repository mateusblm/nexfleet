# Entrega NexFleet v1.0.0

Data: 11/11/2026

## Resultado

Entrega final do PJBL. O NexFleet passou a viver em nove repositórios públicos, com a Frota no MongoDB Atlas, os demais serviços em um Azure SQL com um schema por serviço, uma Azure Function HTTP de eficiência composta pelo BFF em `GET /aggregated-data`, Swagger e AsyncAPI públicos e imagens no Docker Hub. A homologação foi republicada na Azure sem PostgreSQL, ACR e DNS privado, com escala a zero, e passou no smoke público a frio.

## URLs

| O quê | URL |
|---|---|
| Frontend | https://white-mushroom-0cadda010.3.azurestaticapps.net |
| API (APIM) | https://apim-nexfleet-homolog-ukzjodf42myfe.azure-api.net |
| Swagger UI | https://apim-nexfleet-homolog-ukzjodf42myfe.azure-api.net/swagger-ui.html |
| Visão consolidada (com token) | https://apim-nexfleet-homolog-ukzjodf42myfe.azure-api.net/aggregated-data |
| AsyncAPI dos eventos | https://white-mushroom-0cadda010.3.azurestaticapps.net/docs/eventos/ |
| Imagens Docker (`hub.docker.com/r/mateusblm/nexfleet-<svc>`) | [gateway](https://hub.docker.com/r/mateusblm/nexfleet-gateway) · [bff](https://hub.docker.com/r/mateusblm/nexfleet-bff) · [identidade](https://hub.docker.com/r/mateusblm/nexfleet-identidade) · [frota](https://hub.docker.com/r/mateusblm/nexfleet-frota) · [operacoes](https://hub.docker.com/r/mateusblm/nexfleet-operacoes) · [indicadores](https://hub.docker.com/r/mateusblm/nexfleet-indicadores) · [function](https://hub.docker.com/r/mateusblm/nexfleet-function) |

## Repositórios

| Repositório | Conteúdo |
|---|---|
| https://github.com/mateusblm/nexfleet | Guarda-chuva: docs, ADRs, contratos, Compose, Bicep, `quality/` e scripts |
| https://github.com/mateusblm/nexfleet-frontend | Shell React e microfrontends Frota, Operações e Painel |
| https://github.com/mateusblm/nexfleet-gateway | API Gateway e Swagger UI |
| https://github.com/mateusblm/nexfleet-bff | BFF, inclusive `GET /aggregated-data` |
| https://github.com/mateusblm/nexfleet-identidade | Login, JWT e usuários |
| https://github.com/mateusblm/nexfleet-frota | Veículos, motoristas e vínculos (MongoDB) |
| https://github.com/mateusblm/nexfleet-operacoes | Abastecimentos, manutenções e outbox |
| https://github.com/mateusblm/nexfleet-indicadores | Projeções e dashboard |
| https://github.com/mateusblm/nexfleet-function | Notificação de abastecimento e cálculo de eficiência |

## Implementado

- Split do monorepo em nove repositórios com histórico preservado; Maven Wrapper, Dockerfile e CI por repositório; publicação no Docker Hub em tag `v*` (ADR 0042).
- Frota com Spring Data MongoDB, índices únicos e vínculo ativo único por índice parcial (ADR 0039).
- Identidade, Operações, Indicadores e Notificações no SQL Server/Azure SQL: migrações V1 em T-SQL, um schema e um usuário contido por serviço, bootstrap pelo administrador (ADR 0040).
- Outbox no SQL Server com `UPDLOCK, READPAST, ROWLOCK` e hint `INDEX(ix_outbox_pendente)`, na ordem `proxima_tentativa_em, ocorrido_em, id`.
- Function HTTP `CalcularEficiencia` (`POST /api/calcular-eficiencia`, `authLevel = FUNCTION`, até 10.000 itens) e `GET /aggregated-data` no BFF, com retorno parcial em `fontes` e cartão "Visão consolidada" no Painel (ADR 0041).
- Swagger UI única no Gateway e no APIM; página AsyncAPI em `/docs/eventos` no Static Web Apps.
- Bicep sem PostgreSQL, ACR e DNS privado; Azure SQL serverless gratuito; `minReplicas: 0` em todos os Container Apps; Log Analytics com limite de 0,15 GB/dia (ADR 0044).
- Execução local com SQL Server 2022, MongoDB 7.0 e RabbitMQ a partir do guarda-chuva; seed de demonstração.
- ADRs 0039–0044; ADRs de PostgreSQL/ACR/jobs de migração marcadas como substituídas; diagramas C4/UML/DER atualizados.

## Verificações executadas

| Verificação | Resultado |
|---|---|
| Smoke público a frio (`scripts/smoke-publico.sh`, todas as réplicas em 0) | **28/28** verificações em 11/11/2026: frontend, AsyncAPI, 401 sem token, login, CRUD de veículo, abastecimento, `/aggregated-data` com as três fontes `ok`, dashboard, Swagger e OpenAPI dos cinco serviços via APIM, CORS, ausência de PostgreSQL/ACR/DNS privado e TLS mínimo 1.2 no Azure SQL |
| `quality/` (`./mvnw -B -ntp -f quality/pom.xml verify` com os irmãos) | 5 testes, 0 falhas, 0 ignorados: matriz CQ01–CQ12, seções dos diagramas, as oito tabelas migradas e as classes do fluxo crítico conferidas contra o código |
| Isolamento entre schemas (SQL Server local) | usuário `operacoes` recusado (`Msg 229`/`Msg 2760`) ao ler ou criar em outro schema |
| Partida a frio | login levou cerca de 90 s na primeira chamada (Identidade + retomada do SQL serverless) |

## Como executar

Linux, macOS ou WSL, a partir do guarda-chuva:

```bash
scripts/iniciar-local.sh
docker compose up -d
scripts/seed-demo.sh
```

Para compilar o código: `scripts/clonar-tudo.sh` e `docker compose -f compose.yaml -f compose.build.yaml up -d --build`. No macOS, o `seed-demo.sh` precisa do `date` do GNU (`coreutils`). Roteiro completo em [GUIA-EXECUCAO-LOCAL.md](GUIA-EXECUCAO-LOCAL.md); publicação na Azure em [GUIA-INFRAESTRUTURA-AZURE-BICEP.md](GUIA-INFRAESTRUTURA-AZURE-BICEP.md), seção 8.

## Riscos e limitações conhecidos

1. **Partida a frio de ~1 a 2 min:** aqueça o ambiente antes de uma demonstração (`scripts/smoke-publico.sh` faz isso).
2. **POST com 503 na partida a frio pode ter sido gravado:** confira a lista antes de repetir (ADR 0044).
3. **`/aggregated-data` com tempo sequencial:** a Function só é chamada depois de Operações; o pior caso é a soma de dois tempos limite (ADR 0041).
4. **Limite gratuito do Azure SQL:** ao esgotar o mês, o banco pausa até o mês seguinte.
5. **BFF em Java**, e não em Node.js como o enunciado sugere "preferencialmente" (ADR 0043).
6. CQ09 e CQ10 não foram repetidos na nova infraestrutura; as provas são da v0.30.0.
7. Os scripts PowerShell que dependiam do monorepo e do PostgreSQL ficaram como legado; os equivalentes da v1.0.0 são em bash.

## Custos

O único custo fixo é o Service Bus Standard (estimativa da spec: cerca de R$ 60/mês). Azure SQL na oferta gratuita, MongoDB Atlas M0, Static Web Apps Free e Container Apps com escala a zero; APIM Consumption, Function Flex Consumption e Log Analytics cobram por uso. O orçamento de R$ 100/mês continua como alerta.
