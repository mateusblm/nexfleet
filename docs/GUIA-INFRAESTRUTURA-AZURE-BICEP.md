# Guia da infraestrutura Azure com Bicep

Versão de referência: **v0.29.0**, revisada em 11/11/2026, depois da publicação.

O repositório contém:

- a arquitetura de homologação em Bicep;
- os validadores e o `what-if`;
- os scripts que publicaram e testaram a homologação em 10/11/2026.

A homologação está **ativa** em `Central US`, no grupo `rg-nexfleet-homolog`. As decisões e as correções da publicação estão na [ADR 0037](adr/0037-publicacao-homologacao-azure.md).

## 1. Estado atual

- **Homologação publicada:**
  - site: https://white-mushroom-0cadda010.3.azurestaticapps.net
  - API: https://apim-nexfleet-homolog-ukzjodf42myfe.azure-api.net
- **Bicep:** versão 0.49.2 em `.tools/bicep`, conferida por SHA-256. Os 22 tipos do inventário estão modelados, incluindo os três do Azure Communication Services Email, e não há pendência estrutural.
- **Container Apps:** seis, com imagens versionadas, identidade gerenciada e ACR Pull. O perfil `workloadProfile` vale `economico` por padrão; `carga` é usado só durante o CQ09.
- **Mensageria:** Operações publica no Service Bus. Indicadores e Function recebem por assinaturas com regras de filtro nomeadas, com papéis RBAC mínimos.
- **Rede e dados:** VNet com sub-redes delegadas; DNS privado; PostgreSQL sem acesso público, com cinco papéis isolados, 17 migrações e backup de sete dias.
- **Jobs de banco:** migrate, verify e admin (`migration-job.bicep`), executados dentro da VNet.
- **Travas por padrão:** `publicationApproved=false` e `workloadsEnabled=false` nos templates. Toda mutação exige um script com `-Authorize`.
- **Validação:** lint e build offline aprovados. Os templates Bicep não contêm comandos de implantação; a implantação fica nos scripts da seção 7.1.

## 2. Arquivos

| Arquivo | Finalidade |
|---|---|
| `infra/azure/main.bicep` | Escopo da assinatura, grupo, orçamento, travas e composição da plataforma. |
| `infra/azure/modules/platform.bicep` | Rede, dados, mensageria, observabilidade, Function, APIM, frontend, identidades e RBAC. |
| `infra/azure/modules/workloads.bicep` | Os seis serviços Java e suas configurações de ambiente. |
| `infra/azure/modules/container-app.bicep` | Módulo reutilizável de Container App, probes, ingress e escala. |
| `infra/azure/sql/bootstrap-service-roles.sql` | Bootstrap idempotente dos cinco papéis PostgreSQL, sem senha literal. |
| `infra/azure-database/` | Imagem não-root que provisiona os papéis e aplica as 17 migrações Flyway. |
| `infra/azure/resource-requirements.json` | Inventário dos 22 tipos esperados. |
| `infra/azure/migration-job.bicep` | Jobs `migrate`, `verify` e `admin` do banco, executados dentro da VNet. |
| `infra/azure-database/verify.sh` e `bootstrap-admin.sh` | Prova das 17 migrações e do isolamento; criação idempotente do primeiro Administrador, que recebe somente o hash BCrypt. |
| `infra/azure/staticwebapp.config.json` | Rotas, fallback e cabeçalhos do frontend publicado. |
| `quality/azure/homolog.mjs` | Fluxo crítico de homologação pela borda HTTPS. |
| `quality/load/Dockerfile` | Imagem do CQ09 para rodar a carga dentro da região. |
| `scripts/Test-AzureInfrastructure.ps1` | Inventário, travas, lint e build Bicep offline. |
| `scripts/Build-AzureFrontend.ps1` | Build e pacote do shell + três microfrontends. |
| `scripts/Invoke-AzureWhatIf.ps1` | Preflight conectado e `what-if` somente leitura via Azure CLI ou ARM REST. |
| `scripts/Deploy-AzureFoundation.ps1` | Fundação e, com `-EnableWorkloads`, os seis Container Apps e a API no APIM. Aceita `-WorkloadProfile economico` ou `carga`. |
| `scripts/Publish-AzureImages.ps1` | Build e push das seis imagens Java no ACR. |
| `scripts/Publish-AzureDatabaseMigration.ps1` | Imagem de banco e jobs migrate/verify/admin. Grava o relatório exigido por `-EnableWorkloads`. |
| `scripts/Publish-AzureFunction.ps1` | Build, pacote somente com o gatilho Service Bus e publicação OneDeploy da Function. |
| `scripts/Publish-AzureFrontend.ps1` | Build com a URL do APIM e publicação no Static Web Apps. |
| `scripts/Test-AzureHomologation.ps1` | Executa `homolog.mjs` com a conta do Administrador. |
| `scripts/Test-AzureRecovery.ps1` | CQ10: restauração point-in-time cronometrada em servidor temporário, excluído no fim. |
| `scripts/Invoke-AzureDatabaseQuery.ps1` | Consulta SQL somente leitura no PostgreSQL privado, executada dentro da VNet. |

Perfis, planos reais, senhas (`.secrets/`) e relatórios de `what-if`, migração, homologação e CQ10 são locais e ignorados pelo Git.

## 3. Recursos modelados

- grupo de recursos e orçamento com alertas em 50%, 80% e previsão de 100%;
- Log Analytics e Application Insights;
- ACR Basic sem usuário administrador;
- Key Vault com RBAC, soft delete e purge protection;
- Storage Account para Function sem chave compartilhada;
- Service Bus Standard, tópico, assinaturas, filtros, duplicação e DLQ;
- PostgreSQL Flexible Server 18 privado, cinco bancos e backup de sete dias;
- VNet, DNS privado e links de rede;
- Container Apps Environment e seis Container Apps;
- uma identidade gerenciada por workload e papéis mínimos;
- Static Web Apps Free, APIM Consumption e Function Flex Java 21;
- Azure Communication Services Email com domínio gerenciado, quando `notificationRecipientEmail` estiver preenchido.

Esses SKUs estão em uso na homologação publicada. Uma nova implantação em outra assinatura exige revisar custo e aprovações de novo.

## 4. Transporte e e-mail

RabbitMQ permanece no Compose. Na Azure, `MESSAGING_PROVIDER=servicebus`; `DefaultAzureCredential` usa a identidade do workload. A Function recebe `AbastecimentoRegistrado.v1` pela assinatura `notificacoes-abastecimentos-v1`.

O e-mail é controlado pelo parâmetro `notificationRecipientEmail`. Quando ele está preenchido, o Bicep cria Email Communication Services, o domínio `AzureManagedDomain` e Communication Services, todos globais com dados em `United States`. Também concede à identidade da Function o papel `Communication and Email Service Owner` e configura `EMAIL_PROVIDER=azure-communication`, endpoint, remetente `DoNotReply@…` e `AZURE_CLIENT_ID`. Quando o parâmetro está vazio, mantém `captured-local` sem criar nada. Veja a [ADR 0036](adr/0036-email-azure-communication-services.md).

## 5. Validação offline

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\Test-AzureInfrastructure.ps1
```

Resultado esperado:

```text
Infraestrutura Azure válida: 22 tipos modelados, 0 pendente e nenhum comando de implantação embutido nos templates.
```

## 6. Pacote do frontend

`Publish-AzureFrontend.ps1` descobre sozinho o nome do APIM, gera o pacote e publica. Para gerar só o pacote, sem publicar:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\Build-AzureFrontend.ps1 `
  -ApiBaseUrl "https://apim-nexfleet-homolog-ukzjodf42myfe.azure-api.net"
```

O resultado fica em `output/azure-web`. Em outra assinatura, use a URL do APIM criado lá.

## 7. Preparar o what-if

O perfil real precisa estar validado e o plano deve manter deploy desautorizado:

```json
{
  "deploymentAuthorized": false,
  "whatIfAuthorized": true,
  "messagingDecision": "servicebus"
}
```

Disponibilize a senha administrativa temporária somente na sessão:

```powershell
$env:NEXFLEET_AZURE_POSTGRES_ADMIN_PASSWORD = Read-Host `
  "Senha temporária forte do PostgreSQL"

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\Invoke-AzureWhatIf.ps1 `
  -Transport ArmRest `
  -ValidationLevel ProviderNoRbac

Remove-Item Env:NEXFLEET_AZURE_POSTGRES_ADMIN_PASSWORD
```

O script também lê a chave RSA local, codifica o PEM em Base64 para contornar uma falha de serialização do Windows PowerShell 5.1, usa a tag de `VERSION`, elimina parâmetros temporários e executa somente `what-if`. O parâmetro continua marcado como seguro e o Bicep o decodifica somente ao compor o segredo da Identidade. O transporte `ArmRest` usa o endpoint oficial, acompanha respostas assíncronas e grava apenas `status`, `resourceId` e `changeType`.

Em 10/11/2026, houve duas execuções do `what-if` `ProviderNoRbac` em `Central US`, ambas com `Succeeded` e zero exclusões:

- antes do e-mail: 62 criações previstas;
- depois do e-mail, com o ACS: 66 criações previstas e uma implantação lógica.

Depois que o plano real passa a ter `deploymentAuthorized=true`, o script recusa rodar com ele, de propósito. Para uma nova simulação, use uma cópia temporária do plano com `deploymentAuthorized=false` em `-DeploymentPlanPath` e apague-a ao terminar.

A decisão regional e o fallback de transporte estão registrados na [ADR 0035](adr/0035-regiao-permitida-e-what-if-arm-rest.md).

## 7.1 Publicação executada (10/11/2026)

A sequência abaixo publicou a homologação. Cada script repete as chamadas curtas ao ARM e tolera os resets de conexão. As decisões e as correções encontradas estão na [ADR 0037](adr/0037-publicacao-homologacao-azure.md).

```powershell
# 1. Fundação (workloads desligados)
./scripts/Deploy-AzureFoundation.ps1 -Authorize
# 2. Seis imagens Java no ACR (login por Entra ID)
./scripts/Publish-AzureImages.ps1 -Authorize
# 3. Imagem de banco + jobs migrate/verify/admin dentro da VNet
./scripts/Publish-AzureDatabaseMigration.ps1 -AdministratorEmail '<e-mail do administrador>' -Authorize
# 4. Seis Container Apps + API no APIM (exige o relatório de migração aprovado)
./scripts/Deploy-AzureFoundation.ps1 -EnableWorkloads -Authorize
# 5. Function (somente o gatilho Service Bus) e frontend
./scripts/Publish-AzureFunction.ps1 -Authorize
./scripts/Publish-AzureFrontend.ps1 -Authorize
# 6. Fluxo crítico por HTTPS (gera um abastecimento e um e-mail real)
./scripts/Test-AzureHomologation.ps1
# 7. CQ10 com servidor temporário, cronometrado e excluído no fim
./scripts/Test-AzureRecovery.ps1 -Authorize
```

Os passos 5 e 6 exigem o Docker Desktop em execução:

- **Function:** zip criado com `tar -a`, enviado ao endpoint OneDeploy `/api/publish` do Flex Consumption a partir de um contêiner curl. O gatilho RabbitMQ, exclusivo do Compose, fica fora do pacote Azure.
- **Frontend:** `@azure/static-web-apps-cli@2.0.10` em contêiner Node.

A carga do CQ09 na região usa a imagem `quality/load/Dockerfile`. Para o ensaio, aplique `-WorkloadProfile carga` e depois volte para `economico`.

## 8. Barreiras da publicação (todas cumpridas em 10/11/2026)

| Barreira | Como foi cumprida |
|---|---|
| Cota e custo | Cota `ManagedEnvironmentCount` 0/1 em Central US. Cobrança autorizada pelo responsável da conta. |
| E-mail externo | ACS Email com domínio gerenciado, autorizado (ADR 0036). |
| `what-if` revisado | 66 criações e zero exclusões depois da última mudança material antes da fundação. |
| Banco antes dos workloads | Jobs `migrate` e `verify` aprovados. Só então `-EnableWorkloads`, que exige o relatório e liga `databaseMigrationsCompleted`. |
| Imagens e pacotes | Seis imagens `0.29.0` no ACR; Function e frontend publicados pelos scripts. |

Repita o `what-if` (seção 7) depois de qualquer alteração material no Bicep, antes de reimplantar.

## 9. Verificações depois da publicação (executadas)

| Verificação | Resultado |
|---|---|
| Login e APIs por HTTPS | `Test-AzureHomologation.ps1`: 11/11, incluindo 401 sem token, 422 de quilometragem regressiva e painel atualizado por evento. |
| RBAC, segredos e rede privada | Serviços com identidade gerenciada; PostgreSQL sem acesso público; isolamento entre bancos provado pelo `verify.sh`. |
| Service Bus e DLQs | Regras das assinaturas conferidas via ARM; DLQs vazias depois do fluxo. |
| E-mail | Function com `result=ENVIADA` pelo ACS. |
| CQ09 | p95 de 900 ms e 0 falhas com carga na região, perfil `carga` ([evidência](EVIDENCIA-CQ09-DESEMPENHO.md)). |
| CQ10 | Restauração point-in-time: RPO 1,1 min, RTO 8,9 min, 0 divergências ([evidência](EVIDENCIA-CQ10-RECUPERACAO.md)). |
| Logs e métricas | Log Analytics e Application Insights recebendo logs dos serviços, da Function e dos jobs. |

Rotina sugerida antes de uma apresentação: `Test-AzureHomologation.ps1`. Ela cria registros "HML" e envia um e-mail real.

## 10. Custo, orçamento e encerramento

O orçamento de R$ 100/mês é um alerta e **não desliga recursos**. A estimativa pública para o ambiente publicado fica entre R$ 360 e R$ 785/mês, já que PostgreSQL, Service Bus Standard, ACR, APIM, Container Apps e observabilidade cobram enquanto existem. O perfil `carga` aumenta o custo e deve ficar ativo só durante o CQ09.

Em 10/11/2026, o responsável pela conta decidiu manter a homologação ligada até a apresentação. Para encerrar toda a cobrança, exclua o grupo de recursos. A ação é irreversível e apaga também os dados:

```powershell
az group delete --name rg-nexfleet-homolog --yes
```

Depois disso, a sequência da seção 7.1 recria o ambiente em cerca de 1 hora. Os dados de homologação não voltam.

## Referências oficiais

- [Bicep what-if](https://learn.microsoft.com/azure/azure-resource-manager/bicep/deploy-what-if)
- [REST: what-if no escopo da assinatura](https://learn.microsoft.com/rest/api/resources/deployments/whatifatsubscriptionscope)
- [Acompanhar operações assíncronas do ARM](https://learn.microsoft.com/azure/azure-resource-manager/management/async-operations)
- [Azure Functions Flex Consumption](https://learn.microsoft.com/azure/azure-functions/flex-consumption-plan)
- [Azure Service Bus para Java](https://learn.microsoft.com/java/api/overview/azure/messaging-servicebus-readme)
- [Gatilho Service Bus em Azure Functions](https://learn.microsoft.com/azure/azure-functions/functions-bindings-service-bus-trigger)
- [Conexões com identidade gerenciada](https://learn.microsoft.com/azure/azure-functions/manage-connections)
- [Azure Communication Services Email para Java](https://learn.microsoft.com/azure/communication-services/quickstarts/email/send-email)
- [Preços PostgreSQL Flexible Server](https://azure.microsoft.com/pricing/details/postgresql/flexible-server/)
