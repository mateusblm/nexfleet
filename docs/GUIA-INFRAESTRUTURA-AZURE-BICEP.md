# Guia da infraestrutura Azure com Bicep

Versão de referência: **v1.0.0** (entrega final), revisada em 11/11/2026.

O repositório contém a arquitetura de homologação em Bicep, os validadores e o `what-if`. A v1.0.0 troca o desenho da v0.29.0/v0.30.0 por um sem custo fixo além do Service Bus Standard. As decisões da publicação anterior estão na [ADR 0037](adr/0037-publicacao-homologacao-azure.md).

A homologação atual roda em `Central US`, no grupo `rg-nexfleet-homolog`, ainda com o desenho da v0.30.0 (PostgreSQL parado). A v1.0.0 é implantada sobre o mesmo grupo; os recursos antigos são excluídos à mão depois do smoke.

## 1. Desenho da v1.0.0

- **Azure SQL:** um servidor com TLS 1.2 mínimo e endpoint público, regra de firewall "Permitir serviços do Azure" (0.0.0.0) e, opcionalmente, o IP do administrador (`administratorIpAddress`). Um único banco `nexfleet` serverless `GP_S_Gen5_2` com a oferta gratuita (`useFreeLimit: true`) que pausa ao esgotar o limite (`freeLimitExhaustionBehavior: 'AutoPause'`). Um schema e um login por serviço: identidade, operacoes, indicadores e notificacoes. A URL JDBC usa `encrypt=true;trustServerCertificate=false;loginTimeout=60` (o banco pausado leva ~1 min para acordar).
- **MongoDB Atlas M0:** fora da Azure e fora do Bicep. A connection string entra pelo parâmetro seguro `mongodbUri` e vira o secret `MONGODB_URI` da Frota.
- **Container Apps:** seis, com imagens públicas `docker.io/mateusblm/nexfleet-<svc>:<tag>` (`containerImagePrefix` + `containerImageTag`, padrão `v1.0.0`), sem credencial de registry, todos com `minReplicas: 0`. Usuário e senha do banco ficam em secrets do Container App. O perfil `carga` só aumenta CPU e réplicas máximas.
- **Escala a zero e eventos:** Indicadores tem uma regra KEDA `azure-servicebus` (tópico `nexfleet-eventos-v1`, assinatura `indicadores-v1`, até 1 réplica) autenticada pela própria identidade gerenciada, com `Azure Service Bus Data Owner` restrito à assinatura. A Function de notificação escala por evento no Flex Consumption. Operações publica a outbox por job agendado dentro do app: com zero réplicas, os eventos só saem enquanto o app está ativo depois de uma requisição HTTP (o registro sempre chega por HTTP e o app fica ativo alguns minutos).
- **Function:** Flex Consumption com o schema `notificacoes` (`DB_URL`, `DB_USER`, `DB_PASSWORD`). O BFF recebe `EFICIENCIA_FUNCTION_URL` (só a base, `https://<function>`; o BFF acrescenta `/api/calcular-eficiencia`) e o secret `EFICIENCIA_FUNCTION_KEY` (parâmetro `eficienciaFunctionKey`, obtido depois de publicar a Function).
- **APIM:** a API `api` continua com os curingas `/api/*`. A API raiz encaminha ao Gateway `GET /aggregated-data` (com `OPTIONS` para o CORS), `/swagger-ui.html`, `/swagger-ui/*`, `/webjars/*`, `/v3/api-docs`, `/v3/api-docs/*` e `/docs/*`.
- **Static Web Apps:** `staticwebapp.config.json` serve `/docs/eventos` (AsyncAPI renderizado no build do frontend) fora do fallback da SPA. Os assets do web component AsyncAPI ficam no próprio site (`/docs/eventos/vendor/`, copiados no build), então a CSP dessas rotas continua só com `'self'`; ela acrescenta `'unsafe-eval'` em `script-src` porque o parser AsyncAPI embutido valida o contrato com Ajv, que compila validadores com `new Function` (sem isso a página fica em branco). A exceção vale só para `/docs/eventos` e `/docs/eventos/*`; o restante do site mantém `script-src 'self'`.
- **Observabilidade:** Log Analytics com `dailyQuotaGb` 0,15 e Application Insights.
- **Mantidos:** Service Bus Standard, Key Vault, Storage da Function, VNet do Container Apps Environment, identidades gerenciadas e ACS Email.
- **Removidos do Bicep:** PostgreSQL Flexible Server, zona DNS privada `privatelink.postgres.database.azure.com` e o link, ACR e os papéis `AcrPull`, `migration-job.bicep` e os scripts de banco PostgreSQL. A sub-rede `postgresql` fica declarada enquanto `legacyPostgresqlSubnetEnabled=true` (padrão): uma sub-rede em uso não pode ser removida e o servidor antigo é a reversão até o smoke passar. Depois da exclusão do PostgreSQL, reimplante com `false`.
- **Travas:** `publicationApproved=false`, `workloadsEnabled=false` e `databaseMigrationsCompleted=false` por padrão. Os workloads exigem `databaseMigrationsCompleted=true`, que confirma o bootstrap T-SQL dos schemas e logins (as migrações Flyway rodam na subida de cada serviço).

## 2. Arquivos

| Arquivo | Finalidade |
|---|---|
| `infra/azure/main.bicep` | Escopo da assinatura, grupo, orçamento, travas e composição da plataforma. |
| `infra/azure/modules/platform.bicep` | Rede, Azure SQL, mensageria, observabilidade, Function, APIM, frontend, identidades e RBAC. |
| `infra/azure/modules/workloads.bicep` | Os seis serviços Java e suas configurações de ambiente. |
| `infra/azure/modules/container-app.bicep` | Módulo reutilizável de Container App, probes, ingress e escala. |
| `infra/azure/resource-requirements.json` | Inventário dos 21 tipos esperados. |
| `infra/azure/staticwebapp.config.json` | Rotas, fallback e cabeçalhos do frontend publicado, inclusive `/docs/eventos`. |
| `quality/azure/homolog.mjs` | Fluxo crítico de homologação pela borda HTTPS. |
| `scripts/Test-AzureInfrastructure.ps1` | Inventário, travas, regras da v1.0.0, lint e build Bicep offline. |
| `scripts/Get-AzureCostEstimate.ps1` | Estimativa pela API pública de preços (Service Bus + Container Apps). |
| `scripts/Build-AzureFrontend.ps1` | Build e pacote do shell + três microfrontends. |
| `scripts/Invoke-AzureWhatIf.ps1` | Preflight conectado e `what-if` somente leitura via Azure CLI ou ARM REST. |
| `scripts/Deploy-AzureFoundation.ps1` | Fundação e, com `-EnableWorkloads -DatabaseBootstrapConfirmed`, os seis Container Apps e as APIs no APIM. |
| `scripts/Publish-AzureFunction.ps1` | Build, pacote e publicação OneDeploy da Function. |
| `scripts/Publish-AzureFrontend.ps1` | Build com a URL do APIM e publicação no Static Web Apps. |
| `scripts/Test-AzureHomologation.ps1` | Executa `homolog.mjs` com a conta do Administrador. |

Perfis, planos reais, senhas (`.secrets/`) e relatórios de `what-if` são locais e ignorados pelo Git.

## 3. Exemplo de parâmetros (sem segredos)

```json
{
  "location": { "value": "centralus" },
  "resourceGroupName": { "value": "rg-nexfleet-homolog" },
  "resourcePrefix": { "value": "nexfleet" },
  "sqlAdministratorLogin": { "value": "nexfleetadmin" },
  "sqlAdministratorPassword": { "value": "<senha-forte>" },
  "administratorIpAddress": { "value": "" },
  "serviceDatabaseCredentials": { "value": {
    "identidade":   { "login": "nexfleet_identidade",   "password": "<senha-forte>" },
    "operacoes":    { "login": "nexfleet_operacoes",    "password": "<senha-forte>" },
    "indicadores":  { "login": "nexfleet_indicadores",  "password": "<senha-forte>" },
    "notificacoes": { "login": "nexfleet_notificacoes", "password": "<senha-forte>" }
  } },
  "mongodbUri": { "value": "mongodb+srv://frota:<senha>@<cluster>.mongodb.net/frota" },
  "eficienciaFunctionKey": { "value": "<chave-da-function>" },
  "containerImageTag": { "value": "v1.0.0" },
  "workloadsEnabled": { "value": true },
  "databaseMigrationsCompleted": { "value": true },
  "publicationApproved": { "value": true }
}
```

Os demais parâmetros (orçamento, e-mails, `jwtPrivateKeyBase64`) seguem o exemplo completo em `infra/azure/README.md`. O arquivo preenchido nunca entra no Git.

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
Infraestrutura Azure válida: 21 tipos modelados, 0 pendente e nenhum comando de implantação embutido nos templates.
```

## 6. Pacote do frontend

`Publish-AzureFrontend.ps1` descobre sozinho o nome do APIM, gera o pacote e publica. Para gerar só o pacote, sem publicar:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\Build-AzureFrontend.ps1 `
  -ApiBaseUrl "https://apim-nexfleet-homolog-ukzjodf42myfe.azure-api.net"
```

O resultado fica em `output/azure-web`. Em outra assinatura, use a URL do APIM criado lá.

## 7. What-if

Sem PowerShell, o `what-if` roda direto na CLI. O template é do escopo da assinatura (cria o grupo e o orçamento):

```bash
az bicep build --file infra/azure/main.bicep
az bicep lint --file infra/azure/main.bicep
az deployment sub what-if --location centralus \
  --template-file infra/azure/main.bicep \
  --parameters @/caminho/temporario/parametros.json
```

Com o PowerShell, `Invoke-AzureWhatIf.ps1` lê `NEXFLEET_AZURE_SQL_ADMIN_PASSWORD` (obrigatória) e, se definidas, `NEXFLEET_AZURE_MONGODB_URI` e `NEXFLEET_AZURE_EFICIENCIA_FUNCTION_KEY` da sessão, gera senhas temporárias para os logins e grava somente `status`, `resourceId` e `changeType`. O plano real precisa manter `deploymentAuthorized=false` e `whatIfAuthorized=true` ([ADR 0035](adr/0035-regiao-permitida-e-what-if-arm-rest.md)).

Em 11/11/2026, o `what-if` da v1.0.0 contra `rg-nexfleet-homolog` terminou sem erro e sem exclusões. O modo incremental mostra os recursos antigos (PostgreSQL, DNS privado, ACR, jobs) como fora do template: eles só saem por exclusão manual.

## 8. Ordem da publicação da v1.0.0

1. MongoDB Atlas M0 criado à mão (usuário `frota`, lista de IPs aberta) e imagens `v1.0.0` publicadas no Docker Hub pelo CI de cada repositório.
2. Fundação: `Deploy-AzureFoundation.ps1 -Authorize` (cria o Azure SQL, ajusta Log Analytics, Function e APIM; workloads desligados).
3. Bootstrap T-SQL dos schemas e logins no Azure SQL, executado pelo administrador (libere o IP com `-AdministratorIpAddress`).
4. `Publish-AzureFunction.ps1 -Authorize` e leitura da chave da função `calcular-eficiencia`.
5. Workloads: defina `NEXFLEET_AZURE_MONGODB_URI` e `NEXFLEET_AZURE_EFICIENCIA_FUNCTION_KEY` na sessão e rode `Deploy-AzureFoundation.ps1 -EnableWorkloads -DatabaseBootstrapConfirmed -Authorize`.
6. `Publish-AzureFrontend.ps1 -Authorize` e smoke pelas URLs públicas.
7. Depois do smoke verde: excluir PostgreSQL, zona DNS privada, ACR e jobs antigos; reimplantar com `legacyPostgresqlSubnetEnabled=false`.

Antes de uma apresentação, aqueça o banco (primeira conexão depois do auto-pause leva ~1 min) e os Container Apps, que escalam a zero.

## 9. Verificações da publicação da v0.29.0/v0.30.0 (histórico)

Resultados obtidos com o desenho anterior (PostgreSQL privado). As provas CQ09/CQ10 não são repetidas na v1.0.0.

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

O orçamento de R$ 100/mês é um alerta e **não desliga recursos**. Na v1.0.0 o único custo fixo é o Service Bus Standard (~R$ 60/mês). O Azure SQL usa a oferta gratuita e pausa ao esgotar o limite mensal; os Container Apps escalam a zero; APIM Consumption, Function Flex e Log Analytics (até 0,15 GB/dia) cobram por uso. `scripts/Get-AzureCostEstimate.ps1` recalcula a parte fixa pela API pública de preços.

Enquanto o PostgreSQL, o ACR e a zona DNS privada da v0.30.0 existirem, eles continuam cobrando: exclua-os assim que a v1.0.0 passar no smoke (seção 8, passo 7).

Para encerrar toda a cobrança, exclua o grupo de recursos. A ação é irreversível e apaga também os dados:

```bash
az group delete --name rg-nexfleet-homolog --yes
```

## Referências oficiais

- [Bicep what-if](https://learn.microsoft.com/azure/azure-resource-manager/bicep/deploy-what-if)
- [REST: what-if no escopo da assinatura](https://learn.microsoft.com/rest/api/resources/deployments/whatifatsubscriptionscope)
- [Acompanhar operações assíncronas do ARM](https://learn.microsoft.com/azure/azure-resource-manager/management/async-operations)
- [Azure Functions Flex Consumption](https://learn.microsoft.com/azure/azure-functions/flex-consumption-plan)
- [Azure Service Bus para Java](https://learn.microsoft.com/java/api/overview/azure/messaging-servicebus-readme)
- [Gatilho Service Bus em Azure Functions](https://learn.microsoft.com/azure/azure-functions/functions-bindings-service-bus-trigger)
- [Conexões com identidade gerenciada](https://learn.microsoft.com/azure/azure-functions/manage-connections)
- [Azure Communication Services Email para Java](https://learn.microsoft.com/azure/communication-services/quickstarts/email/send-email)
- [Azure SQL Database gratuito (oferta serverless)](https://learn.microsoft.com/azure/azure-sql/database/free-offer)
- [Container Apps: escala](https://learn.microsoft.com/azure/container-apps/scale-app)
