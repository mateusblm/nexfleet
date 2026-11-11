# ADR 0033 — registro controlado, orçamento e e-mail Azure

Data: 08/11/2026.

## Contexto

A descoberta v0.27.0 encontrou cinco provedores pendentes. A equipe aprovou o registro deles, as regiões `Brazil South` e `East US 2`, Service Bus, sete dias de backup PostgreSQL e a criação de um orçamento. A publicação de serviços pagos e o provedor de e-mail ainda precisam de uma decisão separada.

## Decisão

1. Registrar somente `Microsoft.ApiManagement`, `Microsoft.ContainerRegistry`, `Microsoft.DBforPostgreSQL`, `Microsoft.KeyVault` e `Microsoft.ManagedIdentity` por script explícito e idempotente.
2. Configurar orçamento mensal de R$ 100 para o grupo de homologação planejado, com alertas de 50% real, 80% real e 100% previsto.
3. Manter backend e dados em `Brazil South` e metadados do Static Web Apps em `East US 2`.
4. Usar Service Bus como transporte na nuvem e retenção de sete dias para o PostgreSQL.
5. Recomendar Azure Communication Services Email, começando com domínio gerenciado na homologação e domínio próprio verificado para produção.
6. Não registrar `Microsoft.Communication`, criar recursos ou implantar workloads enquanto e-mail, cotas e SKUs pagos não forem aprovados.

## Consequências

- Os tipos planejados deixam de ser bloqueados pelos cinco registros pendentes.
- O orçamento gera alertas, mas não interrompe recursos automaticamente.
- O limite de R$ 100 reduz o risco de consumo acidental, porém exige acompanhamento humano.
- O perfil real continua bloqueando preflight e `what-if` em três decisões: `paidResourcesApproved`, `quotaReviewed` e `notificationProviderApproved`.
- Nenhum segredo, identificador real da assinatura ou e-mail é versionado nos arquivos públicos.

## Alternativas rejeitadas

- Registrar todos os provedores da Azure: escopo excessivo e sem necessidade.
- Usar o orçamento como trava automática: o Cost Management alerta, mas não é um disjuntor.
- Criar o serviço de e-mail apenas pela recomendação: faltam autorização, remetente/domínio e política de destinatários.
