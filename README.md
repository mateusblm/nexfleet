# NexFleet — gestão de frotas em nuvem

Plataforma web para gestão de frotas empresariais. Centraliza veículos, motoristas, vínculos, abastecimentos, manutenções e um painel de custos. Foi desenvolvida como projeto acadêmico de **Arquitetura e Soluções Cloud (PUCPR)**, em cinco sprints.

**Versão:** v0.30.0 · **Status:** Sprints 0 a 4 concluídas · homologação publicada na Azure e validada.

🌐 **Demonstração:** https://white-mushroom-0cadda010.3.azurestaticapps.net
O acesso é por login; peça uma conta ao responsável. O primeiro acesso pode levar cerca de 30 s, enquanto os serviços "acordam".

---

## O que o sistema faz

| Área | Funcionalidades |
|---|---|
| Acesso | Login com JWT; perfis **Administrador** e **Gestor de Frota**; gestão de usuários |
| Frota | Veículos, motoristas e vínculos motorista ↔ veículo com histórico; inativar ou excluir (só sem histórico) |
| Operações | Abastecimentos e manutenções; o hodômetro nunca regride |
| Painel | Gastos, situação da frota e próximas manutenções |
| Notificações | E-mail automático a cada abastecimento, por uma função serverless |

## Arquitetura

```text
Navegador → Shell + 3 microfrontends (React/Vite)
          → API Gateway → BFF → Identidade | Frota | Operações | Indicadores
                                   (cada serviço com o próprio PostgreSQL)
Operações → outbox → broker de eventos → Indicadores (painel) + Função serverless (e-mail)
```

- **Estilos aplicados:** microfrontends, API Gateway + BFF, microsserviços com banco por serviço, arquitetura orientada a eventos (outbox, consumidores idempotentes, retry e DLQ), serverless e Clean Architecture + Vertical Slice, com regras verificadas pelo ArchUnit.
- **Stack:** Java 21 + Spring Boot · React + TypeScript + Vite · PostgreSQL + Flyway · RabbitMQ (local) / Azure Service Bus (nuvem) · Azure Functions · Docker Compose · Bicep.

| Ambiente local (Docker) | Azure (homologação) |
|---|---|
| Shell e microfrontends no Vite | Static Web Apps |
| Spring Cloud Gateway | API Management + Container Apps |
| 6 serviços Java | 6 Container Apps |
| 5 PostgreSQL | PostgreSQL Flexible Server privado (5 bancos isolados) |
| RabbitMQ | Service Bus |
| Function local + captura de e-mail | Azure Functions + Communication Services Email |
| Logs dos contêineres | Application Insights + Log Analytics |

## Executar localmente

**Pré-requisitos:** Docker com Compose v2, `bash`, `curl`, `jq` e `openssl`; ~6 GB de RAM livres (o SQL Server usa 2 GB). Node.js 24 só para as telas. Guia completo: [docs/GUIA-EXECUCAO-LOCAL.md](docs/GUIA-EXECUCAO-LOCAL.md).

```bash
scripts/iniciar-local.sh              # 1ª vez: .env com senhas aleatórias + chave RSA da Identidade
docker compose up -d                  # imagens mateusblm/nexfleet-* do Docker Hub
scripts/seed-demo.sh                  # veículos, motoristas, vínculos, abastecimentos, manutenções
```

Para compilar a partir do código, clone os repositórios lado a lado e use o override:

```bash
scripts/clonar-tudo.sh
docker compose -f compose.yaml -f compose.build.yaml up -d --build
```

Telas (no repositório `nexfleet-frontend`, um terminal por pasta; `NEXFLEET_GATEWAY_URL` só se o Gateway não estiver em 8080):

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
| http://127.0.0.1:15672 | RabbitMQ (`RABBITMQ_USER` / `RABBITMQ_PASSWORD`) |

Para parar: `docker compose down` (dados preservados; `-v` apaga os volumes).

## Azure

A infraestrutura está toda em **Bicep** (`infra/azure`) e é publicada por scripts que exigem `-Authorize`. A ordem é: fundação → imagens → migrações do banco dentro da rede privada → serviços → Function e frontend → testes.

O passo a passo está no [guia de infraestrutura](docs/GUIA-INFRAESTRUTURA-AZURE-BICEP.md), seção 7.1. As decisões estão nas [ADRs 0036 e 0037](docs/adr).

**Qualidade comprovada na nuvem:**

- fluxo ponta a ponta por HTTPS (11/11 verificações);
- **CQ09:** p95 de 0,9 s com 100 usuários;
- **CQ10:** restauração com RPO de 1,1 min e RTO de 8,9 min.

## Documentação

| Para... | Leia |
|---|---|
| Entender, usar e operar o sistema (banco, RabbitMQ, Prometheus, Azure) | [docs/GUIA-USO-E-OPERACAO.md](docs/GUIA-USO-E-OPERACAO.md) |
| Administrar contas e serviços na Azure (senhas, contas, acordar serviços) | [docs/GUIA-ADMINISTRACAO-AZURE.md](docs/GUIA-ADMINISTRACAO-AZURE.md) |
| Executar passo a passo e resolver problemas | [docs/GUIA-EXECUCAO-LOCAL.md](docs/GUIA-EXECUCAO-LOCAL.md) · [macOS](docs/GUIA-EXECUCAO-MACOS.md) |
| Estrutura de pastas e componentes | [docs/GUIA-ESTRUTURA-PROJETO.md](docs/GUIA-ESTRUTURA-PROJETO.md) |
| Decisões de arquitetura | [docs/adr](docs/adr) |
| Aulas passo a passo (33) | [docs/tutorials](docs/tutorials) |
| Requisitos de qualidade CQ01–CQ12 | [docs/MATRIZ-CQ01-CQ12.md](docs/MATRIZ-CQ01-CQ12.md) |
| Andamento das sprints | [docs/STATUS-SPRINTS.md](docs/STATUS-SPRINTS.md) · [CHANGELOG](CHANGELOG.md) |

## Estrutura

```text
services/        6 serviços Java (gateway, bff, identidade, frota, operacoes, indicadores)
frontend/        shell React
microfrontends/  frota, operacoes, painel
functions/       Azure Function de notificação
infra/           Bootstrap do SQL Server, RabbitMQ, Function local e Azure (Bicep)
scripts/         execução local, testes e publicação na Azure
quality/         contratos OpenAPI/AsyncAPI, carga (CQ09) e homologação
docs/            guias, ADRs, aulas e evidências
```

## Segurança

Senhas, chaves e identificadores da assinatura **nunca** são versionados:

- `.env`, `.secrets/` e os perfis da Azure ficam fora do repositório, pelo `.gitignore`;
- cada desenvolvedor gera os seus com `scripts/iniciar-local.sh`;
- na Azure, os serviços se autenticam por identidade gerenciada, e o banco não tem acesso público.

## Equipe

Vinícius dos Reis Góes · Mateus Burlamaqui · Lucas Roussenq · Erik Carvalho
