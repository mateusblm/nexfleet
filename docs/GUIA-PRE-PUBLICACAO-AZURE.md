# Guia de pré-publicação segura na Azure

Versão de referência: **v0.29.0**, revisada em 10/11/2026.

Este guia prepara a homologação do NexFleet sem criar recursos. O pré-check consulta a assinatura, a região e os tipos de recurso com comandos somente de leitura.

## 1. O que esta etapa faz

- valida o formato do perfil de homologação;
- exige orçamento, alertas e aprovações explícitas;
- confirma que a assinatura está habilitada;
- confirma que a região aparece para a assinatura;
- consulta o estado dos provedores e a disponibilidade dos tipos inventariados;
- informa todas as pendências antes da implantação.

Ela não registra provedores, não cria grupo de recursos, não executa Bicep/Terraform e não altera a assinatura.

## 2. Estado atual desta máquina

Em 08/11/2026, o Azure CLI foi instalado e a assinatura **Azure for Students** apareceu como `Enabled` e padrão. Depois de autorização explícita, API Management, Container Registry, PostgreSQL, Key Vault e Managed Identity foram registrados. Em 09/11/2026, `Microsoft.Network` também foi autorizado e registrado; a descoberta passou a confirmar 19/19 tipos. O primeiro `what-if` conectado revelou que a política recusa `Brazil South`. Em 10/11/2026, o usuário autorizou qualquer região compatível, `Central US` foi adotada e o `what-if` `ProviderNoRbac` concluiu com 63 mudanças previstas, sendo 62 criações, uma implantação lógica e zero exclusões. Um orçamento de R$ 100/mês foi configurado com alertas em 50% real, 80% real e 100% previsto. Até esse ponto, nenhum workload, grupo de recursos ou serviço pago havia sido implantado. Ainda em 10/11/2026, depois das autorizações de cobrança, cotas e e-mail, a homologação foi publicada (ver a seção 7.1 do [guia Bicep](GUIA-INFRAESTRUTURA-AZURE-BICEP.md) e a ADR 0037).

## Decisões registradas até a v0.29.0

| Decisão | Estado |
|---|---|
| Região de backend e dados | `Central US`, aprovada e validada |
| Região do Static Web Apps | `Central US`, aprovada e validada |
| Mensageria na Azure | Service Bus, aprovado |
| Backup PostgreSQL | retenção de 7 dias, aprovada |
| Orçamento de alerta | R$ 100/mês, configurado |
| Notificações da primeira publicação | Azure Communication Services Email com domínio gerenciado e destinatário consentido (ADR 0036); `captured-local` permanece como padrão quando o destinatário está vazio |
| Workloads pagos | cobrança autorizada pelo responsável em 10/11/2026; ainda não implantados |

A v0.29.0 modela 19/19 tipos em Bicep, incluindo rede e Container Apps. `Central US` é a única região permitida que suporta os 19 tipos em um único local; o perfil real usa essa região e mantém `dataRegionApproved=true`. Isso comprova compatibilidade e decisão regional, mas não conclui a revisão de cotas nem autoriza cobrança. Ambas foram concluídas depois, em 10/11/2026. Com o ACS Email, o inventário passou a 22 tipos, todos disponíveis em `Central US`.

O orçamento é um alarme financeiro, não um bloqueio de consumo. O valor de R$ 100 foi escolhido como limite conservador para a assinatura estudantil; os alertas permitem interromper a homologação manualmente antes de consumir o crédito disponível.

## 3. Instalar o Azure CLI

No Windows, abra o PowerShell e execute:

```powershell
winget install --exact --id Microsoft.AzureCLI
```

Feche e abra novamente o terminal. No macOS 13 ou mais recente com Homebrew:

```bash
brew update && brew install azure-cli
```

Confirme a instalação:

```powershell
az version
```

A referência oficial de instalação está em [Microsoft Learn — instalar o Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli).

## 4. Entrar sem mudar a assinatura padrão

```powershell
az login
az account list --output table
```

O pré-check recebe o identificador da assinatura em cada consulta. Ele não executa `az account set` nem muda a seleção global do seu terminal.

## 5. Executar a descoberta somente leitura

Na raiz do projeto:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\Get-AzureReadiness.ps1
```

No PowerShell 7/macOS:

```bash
pwsh ./scripts/Get-AzureReadiness.ps1
```

O padrão compara as cinco regiões permitidas pela política desta assinatura: `centralus`, `chilecentral`, `mexicocentral`, `northcentralus` e `spaincentral`. O relatório `infra/azure/preflight-report-*.json` contém o identificador da assinatura, é ignorado pelo Git e não contém senha ou token. A descoberta aceita estados `NotRegistered` como resultado: ela nunca executa `az provider register`.

## 6. Criar o perfil local

Na raiz do NexFleet:

```powershell
Copy-Item `
  .\infra\azure\preflight-profile.example.json `
  .\infra\azure\preflight-profile.json
```

No macOS/Linux:

```bash
cp ./infra/azure/preflight-profile.example.json ./infra/azure/preflight-profile.json
```

`preflight-profile.json` é ignorado pelo Git porque contém o UUID da assinatura e e-mails de alerta. Ele não deve conter senhas, chaves ou connection strings.

## 7. Preencher o perfil

| Campo | Como decidir |
|---|---|
| `subscriptionId` | Copie o UUID da assinatura paga ou estudantil escolhida em `az account list`. |
| `location` | Use o nome técnico aprovado, atualmente `centralus`, depois de confirmar disponibilidade e residência dos dados. |
| `staticWebLocation` | Região separada de metadados do Static Web Apps, atualmente `centralus`. |
| `resourcePrefix` | Prefixo curto, minúsculo e sem hífen, usado futuramente em nomes globais. |
| `resourceGroupName` | Nome planejado do grupo de homologação; nenhum grupo é criado neste passo. |
| `monthlyBudgetAmount` | Limite mensal aprovado na moeda de cobrança da assinatura. Não estime zero. |
| `billingCurrency` | Código de três letras exibido pela cobrança, por exemplo `BRL` ou `USD`. |
| `budgetAlertEmails` | Ao menos um destinatário responsável por custos. |
| `budgetThresholdPercent` | Deve conter alertas em 50%, 80% e 100%. |

As oito aprovações começam em `false`:

| Aprovação | Significado |
|---|---|
| `billingScopeChecked` | Tipo, responsável e escopo de cobrança da assinatura foram conferidos. |
| `spendingProtectionReviewed` | Limite/proteção de gastos e consequências da cobrança foram revisados. |
| `budgetConfigured` | Um orçamento com destinatários e limites foi realmente configurado. |
| `paidResourcesApproved` | A equipe aceitou os SKUs que podem consumir crédito. |
| `dataRegionApproved` | A região principal, a região do Static Web Apps e a residência dos dados foram aprovadas. |
| `quotaReviewed` | Cotas dos serviços planejados foram conferidas. |
| `backupPolicyApproved` | Retenção, PITR e ensaio de restauração foram definidos. |
| `notificationProviderApproved` | Provedor, remetente, destinatário e consentimento do e-mail foram decididos. |

Marque uma aprovação como `true` somente depois que ela acontecer. O perfil de exemplo mantém todas como `false` para não presumir autorização.

## 8. Executar o pré-check

No Windows PowerShell:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\Test-AzurePreflight.ps1
```

No PowerShell 7, inclusive no macOS:

```powershell
pwsh ./scripts/Test-AzurePreflight.ps1
```

Antes de acessar a Azure, o script reprova campos ausentes, orçamento zero, e-mail inválido e qualquer aprovação pendente. Depois consulta:

```text
az account show
az account list-locations
az provider show
az version
```

O uso de `az account list-locations` e `az provider show` segue a documentação oficial de [assinaturas](https://learn.microsoft.com/cli/azure/account) e [provedores/tipos de recurso](https://learn.microsoft.com/azure/azure-resource-manager/management/resource-providers-and-types).

## 9. Recursos conferidos

O inventário atual fica em `infra/azure/resource-requirements.json` e contém 22 tipos:

- Container Apps Environment e Container Apps;
- Virtual Network, Private DNS e link de DNS privado;
- Container Registry;
- PostgreSQL Flexible Server;
- Key Vault;
- Application Insights e Log Analytics;
- Storage Account;
- Static Web Apps, Function App e plano de Functions;
- API Management;
- Service Bus;
- identidade gerenciada, atribuições RBAC e orçamento;
- Communication Services, Email Communication Services e domínio de e-mail (`Microsoft.Communication`, registrado em 10/11/2026).

Um estado `NotRegistered` ou uma região incompatível reprova o pré-check. O script de registro é separado e exige `-Authorize`. Por padrão, ele mantém somente os cinco provedores já aprovados. `Microsoft.Network` só é incluído com o segundo consentimento explícito `-IncludeNetwork`. Static Web Apps é conferido contra `staticWebLocation`; os demais recursos regionais usam `location`.

## Repetir as duas alterações autorizadas

Os comandos abaixo são idempotentes: podem ser executados novamente sem duplicar registros ou orçamento.

```powershell
./scripts/Register-AzureProviders.ps1 -Authorize
./scripts/Set-AzureBudget.ps1 -Authorize
```

O primeiro limita-se a API Management, Container Registry, PostgreSQL, Key Vault e Managed Identity. O segundo lê o perfil local ignorado pelo Git e atualiza o orçamento mensal do grupo de homologação planejado.

Depois de autorização específica para o provedor de rede, use:

```powershell
./scripts/Register-AzureProviders.ps1 -Authorize -IncludeNetwork
```

Esse comando também percorre os cinco provedores anteriores de forma idempotente e solicita somente o registro adicional de `Microsoft.Network` quando necessário. Em 09/11/2026, o registro foi autorizado e concluído. Ele não criou VNet nem outro workload.

Para consultar novamente a política de regiões sem alterar a assinatura:

```powershell
./scripts/Get-AzureRegionPolicy.ps1
```

## Recomendação para e-mail

Recomenda-se [Azure Communication Services Email](https://learn.microsoft.com/azure/communication-services/concepts/email/email-overview) para manter identidade, métricas e cobrança no mesmo provedor. Em homologação, um domínio gerenciado pela Azure simplifica os primeiros testes, embora tenha [limites baixos](https://learn.microsoft.com/azure/communication-services/concepts/service-limits). Para produção, use [domínio próprio verificado por DNS](https://learn.microsoft.com/azure/communication-services/quickstarts/email/add-custom-verified-domains) com SPF e DKIM.

Atualização de 10/11/2026: a autorização foi concedida ([ADR 0036](adr/0036-email-azure-communication-services.md)). A homologação usa domínio gerenciado (`DoNotReply@<guid>.azurecomm.net`) e autenticação por identidade gerenciada. O destinatário consentido fica em `notificationRecipientEmail`, no perfil local ignorado pelo Git. Com o campo vazio, o Bicep volta para `captured-local` e não cria recursos do ACS.

## 10. Orçamento não é bloqueio automático

Alertas de orçamento avisam quando o custo alcança o limite configurado, mas não desligam os recursos. A Microsoft recomenda acompanhar custos e destinatários de alerta; consulte [Cost Management — alertas de gastos](https://learn.microsoft.com/azure/cost-management-billing/costs/cost-mgt-alerts-monitor-usage-spending).

Em assinaturas pagas, confirme moeda, responsável pela cobrança, orçamento e impacto dos SKUs. No Azure for Students, o crédito é limitado e a assinatura pode ser desabilitada quando o saldo termina. Consulte [Azure for Students](https://learn.microsoft.com/azure/education-hub/about-azure-for-students) somente quando esse for o tipo da assinatura.

## 11. Próxima barreira

Um resultado `PREFLIGHT AZURE APROVADO` comprova somente que decisões e disponibilidade foram verificadas. Ele não autoriza automaticamente a criação dos recursos.

O Bicep e o executor de `what-if` já existem. `Microsoft.Network` está registrado, o preflight confirmou 19/19 tipos e o último `what-if` completo em `Central US` terminou com status `Succeeded`, 62 criações previstas, uma implantação lógica e zero exclusões. Em 10/11/2026, a cobrança foi autorizada e `paidResourcesApproved` passou a `true`. A repetição após o isolamento dos bancos foi tentada duas vezes, mas a conexão local com o ARM foi encerrada pelo host remoto; nenhum recurso foi alterado. A verificação inicial de cotas encontrou PostgreSQL `Standard_B1ms`, Container Apps Environment 0/1 e sandbox cores 0/10. Naquele momento, o preflight de implantação bloqueava somente `quotaReviewed` e `notificationProviderApproved`. Ainda em 10/11/2026, as duas aprovações foram concluídas, o preflight foi aprovado com 22/22 tipos, o `what-if` previu 66 criações e zero exclusões, e a homologação foi implantada e validada. Consulte também a [estimativa de custos Azure](ESTIMATIVA-CUSTOS-AZURE.md) e o [Guia da infraestrutura Azure com Bicep](GUIA-INFRAESTRUTURA-AZURE-BICEP.md).
