# ADR 0036 — e-mail externo com Azure Communication Services

Data: 10/11/2026
Estado: aceita; recursos criados somente na implantação autorizada da fundação

## Contexto

A ADR 0033 recomendou o Azure Communication Services (ACS) Email, mas deixou o provedor de e-mail e o registro de `Microsoft.Communication` pendentes de aprovação. A função `NotificarAbastecimento` já possui os dois adaptadores: `captured-local`, que só grava no PostgreSQL, e `azure-communication`, que reserva o envio de forma idempotente e chama o ACS com a identidade gerenciada.

Em 10/11/2026, o responsável pela conta autorizou o envio real das notificações para o próprio e-mail. A mesma consulta conectada confirmou a cota de Container Apps em `Central US`: `ManagedEnvironmentCount` 0/1. O ambiente existente na assinatura é contabilizado como `ExpressEnvironmentCount`, que tem uso de 1 em um limite de 350.

## Decisão

1. Usar o ACS Email com o domínio gerenciado pela Azure (`DoNotReply@<guid>.azurecomm.net`) na homologação.
2. Criar `emailServices`, o domínio `AzureManagedDomain` e `communicationServices` como recursos globais, com residência de dados `United States`, mesma geografia de `Central US`.
3. Autenticar a função pela identidade gerenciada atribuída ao usuário, com o papel `Communication and Email Service Owner` restrito ao recurso ACS. Nenhuma connection string ou chave de acesso é usada.
4. Ler o destinatário de `notificationRecipientEmail` no perfil local ignorado pelo Git. Quando o campo está vazio, o Bicep mantém `EMAIL_PROVIDER=captured-local` e não cria recursos do ACS.
5. Exigir `notificationProviderApproved=true` antes de implantar com um destinatário preenchido.
6. Registrar `Microsoft.Communication` na assinatura. O registro não tem custo.

## Evidência

Em 10/11/2026:

- O preflight `Deployment` foi aprovado com 22 tipos de recurso prontos e `Microsoft.Communication` registrado.
- O `what-if` `ProviderNoRbac` via ARM REST terminou com `Succeeded`: 66 criações previstas, uma implantação lógica e zero exclusões. As quatro criações novas em relação à ADR 0035 são o Email Service, o domínio gerenciado, o Communication Service e a atribuição do papel de envio.
- A conexão com `management.azure.com` continua com resets intermitentes (`WinError 10054`). O `what-if` foi concluído depois de novas tentativas.

## Consequências

- O inventário Azure passa de 19 para 22 tipos de recurso.
- O domínio gerenciado tem limite baixo de envio e não serve para produção. Em produção, será necessário um domínio próprio verificado com SPF, DKIM e DMARC.
- O custo é cobrado por mensagem e é desprezível no volume da homologação.
- Cada abastecimento passa a gerar um e-mail real. A idempotência por `eventId` impede duplicação em uma nova entrega.
- Mudanças no Bicep exigem um novo `what-if` antes da fundação (ADR 0035).

## Alternativas rejeitadas

- SendGrid ou SMTP externo: adicionaria outro fornecedor, além de segredos fora da Azure.
- Domínio próprio já na homologação: exigiria DNS e verificação, sem ganho para a demonstração.
- Chave de acesso do ACS em app setting: contraria a política de segredos (ADR 0033 e Arc42 16.8.1).

## Referências

- [Domínio gerenciado pela Azure para Email Communication Services](https://learn.microsoft.com/azure/communication-services/quickstarts/email/add-azure-managed-domains)
- [Autenticação do Email com Microsoft Entra ID](https://learn.microsoft.com/azure/communication-services/concepts/authentication)
