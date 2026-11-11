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
| Prometheus | Application Insights + Log Analytics |

## Executar localmente

**Pré-requisitos:** Windows com PowerShell e **Docker Desktop** em execução. Node.js e JDK 21 são baixados pelo próprio projeto.

```powershell
Set-ExecutionPolicy -Scope Process Bypass

./scripts/Install-Dependencies.ps1      # 1ª vez: Node, JDK, npm, Maven
./scripts/Initialize-Local.ps1          # 1ª vez: cria .env.sprint0 e as chaves locais
#   → edite .env.sprint0 e defina LOCAL_USER_PASSWORD
./scripts/Start-Local.ps1 -ProvisionUser # 1ª vez (cria o usuário); depois: -NoBuild
```

Em seguida, suba as telas em quatro terminais. Em cada um, rode primeiro `. .\scripts\Use-Local-Toolchain.ps1`:

```powershell
cd frontend;                  npm.cmd run dev   # 5173 (shell)
cd microfrontends/frota;      npm.cmd run dev   # 5174
cd microfrontends/operacoes;  npm.cmd run dev   # 5175
cd microfrontends/painel;     npm.cmd run dev   # 5176
```

| Endereço | Uso |
|---|---|
| http://127.0.0.1:5173 | Sistema (login com `LOCAL_USER_EMAIL` / `LOCAL_USER_PASSWORD`) |
| http://127.0.0.1:15672 | RabbitMQ (`RABBITMQ_USER` / `RABBITMQ_PASSWORD`) |
| http://127.0.0.1:9090 | Prometheus |

Para parar: `./scripts/Stop-Local.ps1`. Os dados são preservados.
Para testar: `./scripts/Test-Project.ps1`.

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
infra/           Docker, RabbitMQ, Prometheus e Azure (Bicep)
scripts/         execução local, testes e publicação na Azure
quality/         contratos OpenAPI/AsyncAPI, carga (CQ09) e homologação
docs/            guias, ADRs, aulas e evidências
```

## Segurança

Senhas, chaves e identificadores da assinatura **nunca** são versionados:

- `.env.sprint0`, `.secrets/` e os perfis da Azure ficam fora do repositório, pelo `.gitignore`;
- cada desenvolvedor gera os seus com `Initialize-Local.ps1`;
- na Azure, os serviços se autenticam por identidade gerenciada, e o banco não tem acesso público.

## Equipe

Vinícius dos Reis Góes · Mateus Burlamaqui · Lucas Roussenq · Erik Carvalho
