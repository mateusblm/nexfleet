# NexFleet — gestão de frotas em nuvem

Plataforma web para gestão de frotas empresariais. Centraliza veículos, motoristas, vínculos, abastecimentos, manutenções, um painel de custos e uma visão consolidada de eficiência. Foi desenvolvida como projeto acadêmico de **Arquitetura e Soluções Cloud (PUCPR)**.

**Versão:** v1.0.0 (entrega final, 11/11/2026) · publicada na Azure e validada por smoke público.

Este é o repositório **guarda-chuva**: documentação, ADRs, contratos, infraestrutura (Bicep e Compose), verificação de qualidade e scripts. O código de cada componente está no próprio repositório (seção [Estrutura](#estrutura)).

---

## O que o sistema faz

| Área | Funcionalidades |
|---|---|
| Acesso | Login com JWT; perfis **Administrador** e **Gestor de Frota**; gestão de usuários |
| Frota | Veículos, motoristas e vínculos motorista ↔ veículo com histórico; inativar ou excluir (só sem histórico) |
| Operações | Abastecimentos e manutenções; o hodômetro nunca regride |
| Painel | Gastos, situação da frota, próximas manutenções e **visão consolidada** (consumo médio e custo por km) |
| Notificações | E-mail automático a cada abastecimento, por uma função serverless |

## Arquitetura

```text
Navegador → Shell + 3 microfrontends (React/Vite)
          → APIM (Azure) → API Gateway → BFF → Identidade | Frota | Operações | Indicadores
                                          └──→ Azure Function HTTP calcular-eficiencia
Frota → MongoDB Atlas
Identidade, Operações, Indicadores, Notificações → Azure SQL (um schema e um usuário por serviço)
Operações → outbox → RabbitMQ (local) / Service Bus (Azure) → Indicadores (painel) + Function (e-mail)
```

- **Estilos aplicados:** microfrontends, API Gateway + BFF, microsserviços com dados isolados por serviço, arquitetura orientada a eventos (outbox, consumidores idempotentes, retry e DLQ), serverless e Clean Architecture + Vertical Slice, com regras verificadas pelo ArchUnit.
- **`GET /aggregated-data`** (BFF): compõe Frota, Operações e a Function de eficiência em um JSON; se uma fonte falha, responde 200 com `fontes.<fonte> = "falhou"` (ADR 0041).
- **Documentação de APIs:** Swagger UI única no Gateway (BFF, Frota, Operações, Identidade e Indicadores) e página AsyncAPI dos eventos em `/docs/eventos`.
- Diagramas C4, UML e DER: [docs/DIAGRAMAS-ARQUITETURA.md](docs/DIAGRAMAS-ARQUITETURA.md). Decisões: [docs/adr](docs/adr) (as da entrega final são as ADRs 0039 a 0044).

| Ambiente local (Docker Compose) | Azure (homologação) |
|---|---|
| Shell e microfrontends no Vite | Static Web Apps |
| Spring Cloud Gateway | API Management (Consumption) + Container Apps |
| 6 serviços Java (imagens do Docker Hub) | 6 Container Apps com escala a zero |
| SQL Server 2022 (um schema por serviço) | Azure SQL Database serverless gratuito |
| MongoDB 7.0 | MongoDB Atlas M0 |
| RabbitMQ | Service Bus Standard |
| Function local + captura de e-mail | Azure Functions (Flex Consumption) + Communication Services Email |

## Tecnologias

- **Backend:** Java 21, Spring Boot 4.1, Spring Cloud Gateway, Spring Security (JWT RSA/JWKS), JDBC + Flyway (T-SQL), Spring Data MongoDB, springdoc-openapi, ArchUnit, JUnit 5 e Testcontainers.
- **Serverless:** Azure Functions Java (gatilhos HTTP, Service Bus e RabbitMQ).
- **Frontend:** React, TypeScript, Vite, Vitest; AsyncAPI web component.
- **Dados e mensageria:** Azure SQL / SQL Server 2022, MongoDB Atlas / MongoDB 7.0, Azure Service Bus / RabbitMQ.
- **Infraestrutura:** Docker, Docker Compose, Docker Hub, GitHub Actions, Bicep, Azure Container Apps, API Management, Static Web Apps, Log Analytics e Application Insights.

## Como rodar localmente

**Pré-requisitos:** Docker com Compose v2, `bash`, `curl`, `jq`, `openssl` e `git`; ~6 GB de RAM livres (o SQL Server usa até 2 GB). Node.js 24 só para as telas. Guia completo: [docs/GUIA-EXECUCAO-LOCAL.md](docs/GUIA-EXECUCAO-LOCAL.md).

```bash
scripts/iniciar-local.sh              # 1ª vez: .env com senhas aleatórias + chave RSA da Identidade
docker compose up -d                  # imagens mateusblm/nexfleet-* do Docker Hub, SQL Server, MongoDB, RabbitMQ
scripts/seed-demo.sh                  # veículos, motoristas, vínculos, abastecimentos, manutenções
```

> **macOS:** `scripts/seed-demo.sh` usa `date -d`, que só existe no `date` do GNU. Instale o `coreutils` (`brew install coreutils`) e ponha o `gnubin` dele no `PATH` antes de rodar o seed.

Para compilar a partir do código, clone os repositórios lado a lado e use o override:

```bash
scripts/clonar-tudo.sh                # clona os 8 repositórios nexfleet-* ao lado deste
docker compose -f compose.yaml -f compose.build.yaml up -d --build
```

Telas (no repositório `nexfleet-frontend`, um terminal por pasta, `npm ci` na primeira vez; `NEXFLEET_GATEWAY_URL` só se o Gateway não estiver em 8080):

```bash
cd frontend && NEXFLEET_GATEWAY_URL=http://127.0.0.1:8080 npm run dev   # 5173 (shell)
cd microfrontends/frota && npm run dev       # 5174
cd microfrontends/operacoes && npm run dev   # 5175
cd microfrontends/painel && npm run dev      # 5176
```

| Endereço | Uso |
|---|---|
| http://127.0.0.1:5173 | Sistema (login com `LOCAL_USER_EMAIL` / `LOCAL_USER_PASSWORD` do `.env`) |
| http://127.0.0.1:8080/swagger-ui.html | Swagger UI (BFF, Frota, Operações, Identidade, Indicadores) |
| http://127.0.0.1:8080/aggregated-data | Visão consolidada (com token) |
| http://127.0.0.1:15672 | RabbitMQ (`RABBITMQ_USER` / `RABBITMQ_PASSWORD`) |

Para parar: `docker compose down` (dados preservados; `-v` apaga os volumes).

Testes: `./mvnw -B -ntp verify` em cada repositório de serviço; `npm ci && npm test && npm run build` em cada pasta do `nexfleet-frontend`; e, aqui, `./mvnw -B -ntp -f quality/pom.xml verify` confere contratos, diagramas e tabelas contra o código dos repositórios irmãos clonados em `../` (ou na pasta indicada por `-Dnexfleet.repos.dir`).

## URLs na nuvem

| O quê | URL |
|---|---|
| Sistema (frontend) | https://white-mushroom-0cadda010.3.azurestaticapps.net |
| API (APIM) | https://apim-nexfleet-homolog-ukzjodf42myfe.azure-api.net |
| Swagger UI | https://apim-nexfleet-homolog-ukzjodf42myfe.azure-api.net/swagger-ui.html |
| Visão consolidada (com token) | https://apim-nexfleet-homolog-ukzjodf42myfe.azure-api.net/aggregated-data |
| AsyncAPI dos eventos | https://white-mushroom-0cadda010.3.azurestaticapps.net/docs/eventos/ |
| Imagens Docker | `https://hub.docker.com/r/mateusblm/nexfleet-<svc>` (`gateway`, `bff`, `identidade`, `frota`, `operacoes`, `indicadores`, `function`) |

O acesso ao sistema é por login; peça uma conta ao responsável.

> **Partida a frio:** para economizar crédito, todos os serviços escalam a zero e o banco pausa sem uso. A primeira chamada depois de um tempo parado pode levar **1 a 2 minutos** ou responder 502/503/504. **Aqueça o ambiente antes de uma demonstração:** `scripts/smoke-publico.sh` faz isso (ver o [guia de infraestrutura, seção 8.8](docs/GUIA-INFRAESTRUTURA-AZURE-BICEP.md)). Se um cadastro der 503 nesse período, confira a lista antes de repetir: ele pode ter sido gravado (ADR 0044).

A infraestrutura está toda em **Bicep** (`infra/azure`). O passo a passo da publicação, em bash, está no [guia de infraestrutura](docs/GUIA-INFRAESTRUTURA-AZURE-BICEP.md), seção 8. Evidência da v1.0.0: smoke público a frio com 28/28 verificações ([entrega v1.0.0](docs/ENTREGA-v1.0.0.md)).

## Estrutura

O NexFleet está em **nove repositórios públicos** em [github.com/mateusblm](https://github.com/mateusblm). Cada um tem README, build próprio e CI; os de serviço publicam a imagem no Docker Hub quando recebem uma tag `v*` (ADR 0042).

| Repositório | Conteúdo |
|---|---|
| [nexfleet](https://github.com/mateusblm/nexfleet) (este) | Documentação, ADRs, contratos OpenAPI/AsyncAPI, Compose, Bicep, bootstrap do SQL, `quality/` e scripts |
| [nexfleet-frontend](https://github.com/mateusblm/nexfleet-frontend) | Shell React e microfrontends Frota, Operações e Painel; página AsyncAPI |
| [nexfleet-gateway](https://github.com/mateusblm/nexfleet-gateway) | API Gateway (Spring Cloud Gateway) e Swagger UI única |
| [nexfleet-bff](https://github.com/mateusblm/nexfleet-bff) | BFF web, inclusive `GET /aggregated-data` |
| [nexfleet-identidade](https://github.com/mateusblm/nexfleet-identidade) | Login, JWT RSA e usuários (Azure SQL, schema `identidade`) |
| [nexfleet-frota](https://github.com/mateusblm/nexfleet-frota) | Veículos, motoristas e vínculos (MongoDB) |
| [nexfleet-operacoes](https://github.com/mateusblm/nexfleet-operacoes) | Abastecimentos, manutenções, hodômetro e outbox (Azure SQL, schema `operacoes`) |
| [nexfleet-indicadores](https://github.com/mateusblm/nexfleet-indicadores) | Projeções por evento e dashboard (Azure SQL, schema `indicadores`) |
| [nexfleet-function](https://github.com/mateusblm/nexfleet-function) | Azure Function: notificação de abastecimento e cálculo de eficiência (schema `notificacoes`) |

Pastas deste repositório:

```text
contracts/   contratos OpenAPI e AsyncAPI
docs/        guias, ADRs, diagramas, aulas, evidências e entregas
infra/       Bicep da Azure, bootstrap do SQL Server, RabbitMQ e Function local
quality/     verificação de contratos e diagramas contra o código, carga (CQ09) e homologação
scripts/     execução local, seed, smoke e publicação (os .ps1 marcados LEGADO são da v0.30.0)
```

## Documentação

| Para... | Leia |
|---|---|
| Executar localmente e resolver problemas | [docs/GUIA-EXECUCAO-LOCAL.md](docs/GUIA-EXECUCAO-LOCAL.md) |
| Publicar na Azure (bash) | [docs/GUIA-INFRAESTRUTURA-AZURE-BICEP.md](docs/GUIA-INFRAESTRUTURA-AZURE-BICEP.md) |
| Entender, usar e operar o sistema | [docs/GUIA-USO-E-OPERACAO.md](docs/GUIA-USO-E-OPERACAO.md) |
| Administrar contas e serviços na Azure | [docs/GUIA-ADMINISTRACAO-AZURE.md](docs/GUIA-ADMINISTRACAO-AZURE.md) |
| Diagramas C4, UML e DER | [docs/DIAGRAMAS-ARQUITETURA.md](docs/DIAGRAMAS-ARQUITETURA.md) |
| Decisões de arquitetura | [docs/adr](docs/adr) |
| Requisitos de qualidade CQ01–CQ12 | [docs/MATRIZ-CQ01-CQ12.md](docs/MATRIZ-CQ01-CQ12.md) |
| Entregas e histórico | [docs/ENTREGA-v1.0.0.md](docs/ENTREGA-v1.0.0.md) · [CHANGELOG](CHANGELOG.md) |

## Segurança

Senhas, chaves e identificadores da assinatura **nunca** são versionados:

- `.env`, `.secrets/` e os perfis e parâmetros da Azure ficam fora do repositório;
- cada desenvolvedor gera os seus com `scripts/iniciar-local.sh`;
- na Azure, segredos ficam em secrets dos Container Apps e nas configurações da Function; Service Bus e e-mail usam identidade gerenciada;
- o Azure SQL e o MongoDB Atlas têm endpoint público com TLS obrigatório; o firewall do SQL aceita só os serviços da Azure e, quando liberado, o IP do administrador; cada serviço só enxerga o próprio schema.

## Alunos

Vinícius dos Reis Góes · Mateus Burlamaqui · Lucas Roussenq · Erik Carvalho
