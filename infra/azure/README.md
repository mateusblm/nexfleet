# Infraestrutura Azure — v1.0.0 sem custo fixo

Esta pasta contém o preflight e a infraestrutura Bicep da homologação. Nenhum arquivo é executado automaticamente e a trava `publicationApproved` começa em `false`.

## Desenho

- **Dados:** um Azure SQL Database serverless (`GP_S_Gen5_2`) com a oferta gratuita (`useFreeLimit: true`, `freeLimitExhaustionBehavior: 'AutoPause'`), um schema e um login por serviço (identidade, operacoes, indicadores, notificacoes). Endpoint público com TLS 1.2 e firewall "Permitir serviços do Azure" (0.0.0.0); `administratorIpAddress` libera opcionalmente o IP do administrador. A Frota usa o MongoDB Atlas M0, configurado fora do Bicep; a connection string chega como secret do Container App.
- **Workloads:** seis Container Apps com imagens públicas `docker.io/mateusblm/nexfleet-<svc>:<tag>` (tag padrão `v1.0.0`), sem bloco `registries`, todos com `minReplicas: 0`. Usuário e senha do banco, `MONGODB_URI` e `EFICIENCIA_FUNCTION_KEY` ficam em secrets do Container App.
- **Function:** Flex Consumption com `DB_URL`/`DB_USER`/`DB_PASSWORD` do schema `notificacoes`. O BFF recebe `EFICIENCIA_FUNCTION_URL` (só a base, `https://<function>`; o BFF acrescenta `/api/calcular-eficiencia`) e a chave da função.
- **Borda:** APIM Consumption com a API `api` (curinga para `/api/*`) e a API raiz que encaminha ao Gateway `GET /aggregated-data`, `/swagger-ui.html`, `/swagger-ui/*`, `/webjars/*`, `/v3/api-docs[/*]` e `/docs/*`. O Static Web App serve `/docs/eventos` (AsyncAPI em HTML estático).
- **Observabilidade:** Log Analytics com limite diário de 0,15 GB.
- **Removidos:** PostgreSQL Flexible Server, zona DNS privada e link, ACR com `AcrPull` e os jobs de migração. O modo incremental não apaga o que já existe: a exclusão dos recursos antigos é manual, depois do smoke da v1.0.0. A sub-rede `postgresql` continua declarada enquanto `legacyPostgresqlSubnetEnabled=true` (padrão), porque uma sub-rede em uso não pode ser removida.

O único custo fixo que sobra é o Service Bus Standard. Custos variáveis: APIM, Container Apps acima da franquia, Function e Log Analytics.

## Arquivos

- `main.bicep`: grupo, orçamento, travas e composição da plataforma.
- `modules/platform.bicep`: rede, Azure SQL, mensageria, Function, borda, identidades e RBAC.
- `modules/workloads.bicep`: seis Container Apps com imagens do Docker Hub.
- `modules/container-app.bicep`: módulo reutilizável de workload, ingress, probes e escala.
- `resource-requirements.json`: provedores e tipos de recurso esperados (21).
- `staticwebapp.config.json`: rotas, fallback e cabeçalhos do frontend, inclusive `/docs/eventos`. Os assets do web component AsyncAPI ficam no próprio site (`/docs/eventos/vendor/`, copiados no build), então a CSP dessas rotas continua só com `'self'`; ela acrescenta `'unsafe-eval'` em `script-src` porque o parser AsyncAPI embutido valida o contrato com Ajv, que compila validadores com `new Function` (sem isso a página fica em branco). A exceção vale só para `/docs/eventos` e `/docs/eventos/*`; o restante do site mantém `script-src 'self'`.
- `preflight-profile.*.json`, `deployment-plan.example.json`: perfil e plano, sem segredo real.
- `bicepconfig.json`: regras do linter tratadas como barreiras de segurança.

## Parâmetros (exemplo sem segredos)

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "location": { "value": "centralus" },
    "resourceGroupName": { "value": "rg-nexfleet-homolog" },
    "resourcePrefix": { "value": "nexfleet" },
    "monthlyBudgetAmount": { "value": 100 },
    "budgetStartDate": { "value": "2026-11-01T03:00:00Z" },
    "budgetEndDate": { "value": "2027-11-01T03:00:00Z" },
    "budgetAlertEmails": { "value": ["<email-do-responsavel>"] },
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
    "jwtPrivateKeyBase64": { "value": "<PEM PKCS#8 em Base64>" },
    "workloadsEnabled": { "value": true },
    "databaseMigrationsCompleted": { "value": true },
    "publicationApproved": { "value": true }
  }
}
```

Nunca commite esse arquivo preenchido. `databaseMigrationsCompleted=true` só depois do bootstrap T-SQL dos schemas e logins; as migrações Flyway rodam na subida de cada serviço.

## Validação

```bash
az bicep build --file infra/azure/main.bicep
az bicep lint --file infra/azure/main.bicep
# Somente leitura: o template é do escopo da assinatura
az deployment sub what-if --location centralus \
  --template-file infra/azure/main.bicep --parameters @<arquivo-temporario>.json
```

`scripts/Test-AzureInfrastructure.ps1` repete o lint e o build e confere o inventário, as travas, a ausência de PostgreSQL/ACR/DNS privado, `minReplicas: 0`, a oferta gratuita do SQL e o limite do Log Analytics. `scripts/Invoke-AzureWhatIf.ps1` lê `NEXFLEET_AZURE_SQL_ADMIN_PASSWORD` (e, opcionalmente, `NEXFLEET_AZURE_MONGODB_URI` e `NEXFLEET_AZURE_EFICIENCIA_FUNCTION_KEY`) da sessão.

Scripts que criam ou alteram recursos exigem `-Authorize`: `Deploy-AzureFoundation.ps1` (com `-EnableWorkloads -DatabaseBootstrapConfirmed` para os workloads), `Publish-AzureFunction.ps1` e `Publish-AzureFrontend.ps1`. O roteiro completo da publicação está em `docs/GUIA-INFRAESTRUTURA-AZURE-BICEP.md`.
