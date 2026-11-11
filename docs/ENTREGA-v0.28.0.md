# Entrega v0.28.0 — preparação Azure autorizada

Data: 08/11/2026.

## Resultado

A assinatura Azure estudantil recebeu somente as alterações explicitamente aprovadas: cinco registros de provedor e um orçamento mensal de R$ 100. A arquitetura, a execução local e o roteiro de macOS foram documentados. Nenhum workload foi implantado.

## Executado na assinatura

| Item | Resultado |
|---|---|
| API Management | provedor `Registered` |
| Container Registry | provedor `Registered` |
| PostgreSQL Flexible Server | provedor `Registered` |
| Key Vault | provedor `Registered` |
| Managed Identity | provedor `Registered` |
| Orçamento | R$ 100/mês |
| Alertas | 50% real, 80% real e 100% previsto |
| Tipos prontos nas regiões candidatas | 16/16 |
| Workloads implantados | 0 |

Registrar um provedor habilita o namespace na assinatura; não cria uma instância do serviço. O orçamento monitora o grupo planejado e não desliga recursos automaticamente.

## Decisões registradas

- backend/dados em `Brazil South`;
- Static Web Apps em `East US 2`;
- Service Bus como mensageria Azure;
- backup PostgreSQL por sete dias;
- Azure Communication Services Email recomendado, mas ainda não autorizado/configurado.

## Arquivos entregues

- `scripts/Register-AzureProviders.ps1`;
- `scripts/Set-AzureBudget.ps1`;
- `docs/GUIA-EXECUCAO-MACOS.md`;
- ADR 0033 e Aula 32;
- guias Azure e estado das sprints atualizados.

## O que permanece bloqueado

- aprovação dos SKUs pagos;
- revisão de cotas da assinatura estudantil;
- aprovação/configuração do provedor de e-mail;
- preflight conectado completo e `what-if`;
- adaptação de RabbitMQ para Service Bus;
- criação da rede, dados, workloads e publicação HTTPS;
- repetição de CQ09 e CQ10 na homologação.

O perfil real mantém `paidResourcesApproved`, `quotaReviewed` e `notificationProviderApproved` como `false`. Assim, os próximos comandos de nuvem continuam bloqueados por projeto.

## Verificação

- sintaxe dos cinco scripts Azure aprovada;
- descoberta offline e template público aprovados;
- lint/build Bicep aprovados, com 15 tipos modelados e Container Apps ainda pendente de migração de runtime;
- repetição idempotente confirmou os cinco provedores como `Registered`;
- repetição idempotente confirmou orçamento de BRL 100/mês;
- descoberta conectada encontrou 16/16 tipos prontos em alguma região candidata;
- preflight real bloqueou somente `paidResourcesApproved`, `quotaReviewed` e `notificationProviderApproved`.
- suíte completa aprovada: 4 testes de qualidade/contratos, 172 testes Java, 8 testes da Function, 47 testes frontend e quatro builds Vite.
