# Guia da infraestrutura Azure com Bicep

Versão de referência: **v1.0.0** (entrega final), revisada em 11/11/2026.

O repositório contém a arquitetura de homologação em Bicep, os validadores e o `what-if`. A v1.0.0 troca o desenho da v0.29.0/v0.30.0 por um sem custo fixo além do Service Bus Standard. As decisões da publicação anterior estão na [ADR 0037](adr/0037-publicacao-homologacao-azure.md).

A homologação roda em `Central US`, no grupo `rg-nexfleet-homolog`, com o desenho da v1.0.0, publicado em 11/11/2026 sobre o mesmo grupo da v0.30.0. Os recursos antigos (PostgreSQL, ACR, DNS privado e jobs) foram excluídos à mão depois do smoke (seção 8.9).

- Frontend: https://white-mushroom-0cadda010.3.azurestaticapps.net
- API (APIM): https://apim-nexfleet-homolog-ukzjodf42myfe.azure-api.net (`/swagger-ui.html`, `/aggregated-data`)
- AsyncAPI: https://white-mushroom-0cadda010.3.azurestaticapps.net/docs/eventos/

## 1. Desenho da v1.0.0

- **Azure SQL:** um servidor com TLS 1.2 mínimo e endpoint público, regra de firewall "Permitir serviços do Azure" (0.0.0.0) e, opcionalmente, o IP do administrador (`administratorIpAddress`). Um único banco `nexfleet` serverless `GP_S_Gen5_2` com a oferta gratuita (`useFreeLimit: true`) que pausa ao esgotar o limite (`freeLimitExhaustionBehavior: 'AutoPause'`). Um schema e um usuário contido por serviço, com o mesmo nome do schema: `identidade`, `operacoes`, `indicadores` e `notificacoes` (criados pelo `infra/sqlserver/bootstrap.sql`). A URL JDBC usa `encrypt=true;trustServerCertificate=false;loginTimeout=60` (o banco pausado leva ~1 min para acordar).
- **MongoDB Atlas M0:** fora da Azure e fora do Bicep. A connection string entra pelo parâmetro seguro `mongodbUri` e vira o secret `MONGODB_URI` da Frota.
- **Container Apps:** seis, com imagens públicas `docker.io/mateusblm/nexfleet-<svc>:<tag>` (`containerImagePrefix` + `containerImageTag`, padrão `v1.0.0`), sem credencial de registry, todos com `minReplicas: 0`. Usuário e senha do banco ficam em secrets do Container App. O perfil `carga` só aumenta CPU e réplicas máximas.
- **Escala a zero e eventos:** Indicadores tem uma regra KEDA `azure-servicebus` (tópico `nexfleet-eventos-v1`, assinatura `indicadores-v1`, até 1 réplica) autenticada pela própria identidade gerenciada, com `Azure Service Bus Data Owner` restrito à assinatura. A Function de notificação escala por evento no Flex Consumption. Operações publica a outbox por job agendado dentro do app: com zero réplicas, os eventos só saem enquanto o app está ativo depois de uma requisição HTTP (o registro sempre chega por HTTP e o app fica ativo alguns minutos).
- **Function:** Flex Consumption com o schema `notificacoes` (`DB_URL`, `DB_USER`, `DB_PASSWORD`). O BFF recebe `EFICIENCIA_FUNCTION_URL` (só a base, `https://<function>`; o BFF acrescenta `/api/calcular-eficiencia`) e o secret `EFICIENCIA_FUNCTION_KEY` (parâmetro `eficienciaFunctionKey`, obtido depois de publicar a Function).
- **APIM:** a API `api` continua com os curingas `/api/*`. A API raiz encaminha ao Gateway `GET /aggregated-data` (com `OPTIONS` para o CORS), `/swagger-ui.html`, `/swagger-ui/*`, `/webjars/*`, `/v3/api-docs`, `/v3/api-docs/*` e `/docs/*`.
- **Static Web Apps:** `staticwebapp.config.json` serve `/docs/eventos` (AsyncAPI renderizado no build do frontend) fora do fallback da SPA. Os assets do web component AsyncAPI ficam no próprio site (`/docs/eventos/vendor/`, copiados no build), então a CSP dessas rotas continua só com `'self'`; ela acrescenta `'unsafe-eval'` em `script-src` porque o parser AsyncAPI embutido valida o contrato com Ajv, que compila validadores com `new Function` (sem isso a página fica em branco). A exceção vale só para `/docs/eventos` e `/docs/eventos/*`; o restante do site mantém `script-src 'self'`.
- **Observabilidade:** Log Analytics com `dailyQuotaGb` 0,15 e Application Insights.
- **Mantidos:** Service Bus Standard, Key Vault, Storage da Function, VNet do Container Apps Environment, identidades gerenciadas e ACS Email.
- **Removidos do Bicep:** PostgreSQL Flexible Server, zona DNS privada `privatelink.postgres.database.azure.com` e o link, ACR e os papéis `AcrPull`, `migration-job.bicep` e os scripts de banco PostgreSQL. A sub-rede `postgresql` fica declarada enquanto `legacyPostgresqlSubnetEnabled=true` (padrão): uma sub-rede em uso não pode ser removida e o servidor antigo é a reversão até o smoke passar. Depois da exclusão do PostgreSQL, reimplante com `false`.
- **Travas:** `publicationApproved=false`, `workloadsEnabled=false` e `databaseMigrationsCompleted=false` por padrão. Os workloads exigem `databaseMigrationsCompleted=true`, que confirma o bootstrap T-SQL dos schemas e dos usuários (um por serviço, com o nome do schema) (as migrações Flyway rodam na subida de cada serviço).

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
| `scripts/Build-AzureFrontend.ps1` | **Legado (monorepo):** build e pacote do shell + três microfrontends a partir de `frontend/` e `microfrontends/` do próprio repositório. Na v1.0.0, use a seção 8.6. |
| `scripts/Invoke-AzureWhatIf.ps1` | Preflight conectado e `what-if` somente leitura via Azure CLI ou ARM REST. |
| `scripts/Deploy-AzureFoundation.ps1` | Fundação e, com `-EnableWorkloads -DatabaseBootstrapConfirmed`, os seis Container Apps e as APIs no APIM. |
| `scripts/Publish-AzureFunction.ps1` | **Legado (monorepo):** espera `functions/notificar-abastecimento` e empacota só o gatilho Service Bus, sem `CalcularEficiencia`. Na v1.0.0, use a seção 8.4. |
| `scripts/Publish-AzureFrontend.ps1` | Publicação no Static Web Apps; o build depende do `Build-AzureFrontend.ps1` (legado). Com `-SkipBuild`, publica um `output/azure-web` montado como na seção 8.6. |
| `scripts/Test-AzureHomologation.ps1` | **Legado (v0.30.0):** executa `homolog.mjs` com a conta criada pelo antigo `Publish-AzureDatabaseMigration.ps1` (removido). Na v1.0.0, use `scripts/smoke-publico.sh`. |
| `infra/sqlserver/bootstrap.sql` | Usuários contidos e schemas por serviço no Azure SQL (seção 8.3). |
| `scripts/smoke-publico.sh` | Smoke da v1.0.0 pelas URLs públicas, com evidências (seção 8.8). |
| `scripts/seed-demo.sh` | Dados de demonstração pela API pública (seção 8.8). |

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
    "identidade":    { "login": "identidade",   "password": "<senha-forte>" },
    "operacoes":     { "login": "operacoes",    "password": "<senha-forte>" },
    "indicadores":   { "login": "indicadores",  "password": "<senha-forte>" },
    "notificacoes":  { "login": "notificacoes", "password": "<senha-forte>" }
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

## 8. Publicação da v1.0.0 passo a passo (bash)

A v1.0.0 foi publicada em 11/11/2026 com os comandos abaixo, em `bash`, a partir do guarda-chuva com os repositórios irmãos clonados ao lado (`scripts/clonar-tudo.sh`). Eles equivalem aos scripts PowerShell da seção 2, que ainda esperam o layout do monorepo (`services/`, `functions/`, `frontend/` dentro do mesmo repositório) e por isso ficam como legado nos passos de Function e frontend.

Requisitos: Azure CLI com `az login`, `sqlcmd`, `jq`, `curl`, `zip`, Docker, JDK 21 e Node.js 24. Nenhum valor secreto aparece nos comandos: senhas e chaves ficam em arquivos de parâmetros **fora do Git** (por exemplo, em `~/.nexfleet-azure/`) e são lidas com `jq` ou digitadas com `read -s`.

```bash
RG=rg-nexfleet-homolog
LOC=centralus
PARAMS_A=~/.nexfleet-azure/params-fase-a.json   # publicationApproved=true, workloadsEnabled=false
PARAMS_B=~/.nexfleet-azure/params-fase-b.json   # + workloadsEnabled=true, databaseMigrationsCompleted=true,
                                                #   mongodbUri e eficienciaFunctionKey
```

Os dois arquivos seguem o exemplo da seção 3 (formato completo em `infra/azure/README.md`). Em `serviceDatabaseCredentials`, o `login` de cada serviço é o **nome do schema** (`identidade`, `operacoes`, `indicadores`, `notificacoes`), porque é esse o usuário que o `bootstrap.sql` cria.

### 8.1 Antes da Azure

1. **MongoDB Atlas M0** criado à mão: usuário `frota`, lista de IPs aberta (os Container Apps não têm IP de saída fixo). Acrescente `serverSelectionTimeoutMS=3000` à URI, para o readiness da Frota não esperar 30 s quando o Atlas estiver fora. A URI vai para `mongodbUri` em `PARAMS_B`.
2. **Imagens:** a tag `v1.0.0` em cada repositório de serviço dispara o CI, que publica `mateusblm/nexfleet-<svc>:v1.0.0` e `:latest` no Docker Hub (exige os secrets `DOCKERHUB_USERNAME` e `DOCKERHUB_TOKEN`).

### 8.2 Fase A: fundação, sem workloads

```bash
az deployment sub create --name nexfleet-v1-fase-a --location "$LOC" \
  --template-file infra/azure/main.bicep --parameters @"$PARAMS_A"

SQL_SERVER=$(az sql server list -g "$RG" --query '[0].name' -o tsv)
FUNC=$(az functionapp list -g "$RG" --query '[0].name' -o tsv)
```

A fase A cria o Azure SQL, o Service Bus, o Log Analytics, a Function vazia, o APIM e o Static Web App. Para o passo seguinte, o IP do administrador precisa estar liberado no firewall do SQL: preencha `administratorIpAddress` em `PARAMS_A`.

### 8.3 Bootstrap do Azure SQL (administrador)

O `bootstrap.sql` cria os quatro usuários contidos e os schemas; as senhas são as mesmas de `serviceDatabaseCredentials` (ADR 0040).

```bash
read -rsp 'Senha do administrador SQL: ' SQLCMDPASSWORD; echo; export SQLCMDPASSWORD
export NEXFLEET_DB=nexfleet
for s in identidade operacoes indicadores notificacoes; do
  export "${s^^}_DB_PASSWORD=$(jq -r ".parameters.serviceDatabaseCredentials.value.$s.password" "$PARAMS_B")"
done
SQL_ADMIN=$(jq -r '.parameters.sqlAdministratorLogin.value' "$PARAMS_B")

sqlcmd -S "$SQL_SERVER.database.windows.net" -d nexfleet -U "$SQL_ADMIN" -b \
  -i infra/sqlserver/bootstrap.sql
```

Identidade, Operações e Indicadores aplicam a própria migração Flyway na subida. A Function não executa Flyway: aplique a `V1` do schema `notificacoes` como o Compose faz (serviços `notificacoes-artefato` e `notificacoes-migracoes`), lendo a migração do jar da imagem da Function:

```bash
docker volume create nexfleet-func-artefato
docker run --rm -v nexfleet-func-artefato:/artefato --entrypoint sh mateusblm/nexfleet-function:v1.0.0 \
  -c 'cp /home/site/wwwroot/notificar-abastecimento-*.jar /artefato/'
docker run --rm -v nexfleet-func-artefato:/artefato:ro -e FLYWAY_PASSWORD="$NOTIFICACOES_DB_PASSWORD" \
  flyway/flyway:13.12.0-alpine \
  "-url=jdbc:sqlserver://$SQL_SERVER.database.windows.net:1433;databaseName=nexfleet;encrypt=true;trustServerCertificate=false;loginTimeout=60" \
  -user=notificacoes -schemas=notificacoes -defaultSchema=notificacoes -createSchemas=false \
  -jarDirs=/artefato -locations=classpath:db/migration migrate
docker volume rm nexfleet-func-artefato
```

### 8.4 Publicar a Function (OneDeploy) e ler a chave

O pacote leva `CalcularEficiencia` e `NotificarAbastecimentoServiceBus`. O gatilho RabbitMQ é só do ambiente local e, na Azure, gera erro de indexação mesmo desativado (ADR 0037); o zip precisa usar `/` nos caminhos.

```bash
(cd ../nexfleet-function && ./mvnw -B -ntp clean package)
APP_DIR=$(ls -d ../nexfleet-function/target/azure-functions/*/ | head -1)
PACOTE=$(mktemp -d)
cp -r "$APP_DIR". "$PACOTE/"
rm -rf "$PACOTE/NotificarAbastecimentoRabbit" "$PACOTE/local.settings.json"
(cd "$PACOTE" && zip -qr ../nexfleet-func.zip .)

TOKEN=$(az account get-access-token --query accessToken -o tsv)
curl -sS -o /dev/null -w '%{http_code}\n' -X POST \
  -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/zip' \
  --data-binary @"$PACOTE/../nexfleet-func.zip" \
  "https://$FUNC.scm.azurewebsites.net/api/publish?RemoteBuild=false&Deployer=nexfleet"
unset TOKEN

az functionapp function list -g "$RG" -n "$FUNC" --query '[].name' -o tsv   # as duas funções
```

A chave da função vai para `eficienciaFunctionKey` em `PARAMS_B`, sem passar pela tela:

```bash
CHAVE=$(az functionapp function keys list -g "$RG" -n "$FUNC" \
  --function-name CalcularEficiencia --query default -o tsv)
jq --arg k "$CHAVE" '.parameters.eficienciaFunctionKey.value = $k' "$PARAMS_B" > "$PARAMS_B.tmp" \
  && mv "$PARAMS_B.tmp" "$PARAMS_B" && chmod 600 "$PARAMS_B"
unset CHAVE
```

### 8.5 Fase B: workloads

```bash
az deployment sub create --name nexfleet-v1-fase-b --location "$LOC" \
  --template-file infra/azure/main.bicep --parameters @"$PARAMS_B"
```

Cria os seis Container Apps (imagens `docker.io/mateusblm/nexfleet-<svc>:v1.0.0`, `minReplicas: 0`), a API `api` e a API raiz no APIM (`/aggregated-data`, Swagger e `/docs/*`).

### 8.6 Frontend no Static Web Apps

Mesmo pacote do `Build-AzureFrontend.ps1`: shell na raiz, microfrontends em `/mfes/<nome>`, o CSS de cada remoto no `index.html` e o `staticwebapp.config.json` (com `/docs/eventos`). O `sed -i` abaixo é o do GNU (no macOS, use o `gsed` do pacote `gnu-sed`).

```bash
API="https://$(az apim list -g "$RG" --query '[0].name' -o tsv).azure-api.net"
OUT=$(mktemp -d)/azure-web; mkdir -p "$OUT/mfes"

for app in frontend microfrontends/frota microfrontends/operacoes microfrontends/painel; do
  (cd "../nexfleet-frontend/$app" && npm ci && VITE_API_BASE_URL="$API" npm run build)
done
cp -r ../nexfleet-frontend/frontend/dist/. "$OUT/"
for m in frota operacoes painel; do
  mkdir -p "$OUT/mfes/$m" && cp -r "../nexfleet-frontend/microfrontends/$m/dist/." "$OUT/mfes/$m/"
done
sed -i 's|</head>|    <link rel="stylesheet" href="/mfes/frota/remoteEntry.css" />\n    <link rel="stylesheet" href="/mfes/operacoes/remoteEntry.css" />\n    <link rel="stylesheet" href="/mfes/painel/remoteEntry.css" />\n  </head>|' "$OUT/index.html"
cp infra/azure/staticwebapp.config.json "$OUT/"

SWA=$(az staticwebapp list -g "$RG" --query '[0].name' -o tsv)
SWA_TOKEN=$(az staticwebapp secrets list -g "$RG" -n "$SWA" --query properties.apiKey -o tsv)
npx --yes @azure/static-web-apps-cli@2.0.10 deploy "$OUT" --env production \
  --deployment-token "$SWA_TOKEN" --no-use-keychain
unset SWA_TOKEN
WEB="https://$(az staticwebapp show -g "$RG" -n "$SWA" --query defaultHostname -o tsv)"
```

### 8.7 Usuário inicial

**Não há usuário na nuvem depois da implantação.** O `LocalSeedConfig` da Identidade é só do ambiente local e nunca é habilitado na Azure. O primeiro usuário é inserido pelo administrador SQL, com a senha transformada em hash BCrypt de custo 12 no próprio computador (a senha não vai ao banco nem ao histórico do shell):

```bash
EMAIL='gestor@exemplo.com'      # TROQUE (minúsculas, sem espaços)
PERFIL='GESTOR_FROTA'           # ou ADMINISTRADOR, para gerenciar usuários pela tela
read -rsp 'Senha (mínimo 12 caracteres): ' NX_SENHA; echo; export NX_SENHA
HASH=$(docker run --rm -e NX_SENHA python:3.13-slim sh -c \
  'pip install -q bcrypt==4.2.1 >/dev/null 2>&1 && python -c "import bcrypt,os; print(bcrypt.hashpw(os.environ[\"NX_SENHA\"].encode(), bcrypt.gensalt(12)).decode())"' | tail -1)
[[ "$HASH" =~ ^\$2[aby]\$12\$.{53}$ ]] || echo 'Falha ao gerar o hash.'

sqlcmd -S "$SQL_SERVER.database.windows.net" -d nexfleet -U "$SQL_ADMIN" -b -Q \
  "INSERT INTO identidade.usuario (id, email, senha_hash, ativo, perfil) VALUES (NEWID(), N'$EMAIL', '$HASH', 1, '$PERFIL');"
unset HASH
```

Guarde e-mail e senha fora do Git (por exemplo, em `~/.nexfleet-azure/`). Para trocar a senha depois, gere outro hash e faça `UPDATE identidade.usuario SET senha_hash = '...' WHERE email = N'...'`.

### 8.8 Seed de demonstração e smoke

```bash
NEXFLEET_API="$API" NEXFLEET_EMAIL="$EMAIL" NEXFLEET_SENHA="$NX_SENHA" scripts/seed-demo.sh
NEXFLEET_API="$API" NEXFLEET_WEB="$WEB" NEXFLEET_EMAIL="$EMAIL" NEXFLEET_SENHA="$NX_SENHA" \
  scripts/smoke-publico.sh /caminho/fora-do-git/evidencias-smoke
unset NX_SENHA SQLCMDPASSWORD
```

`seed-demo.sh` cria veículos, motoristas, vínculos, abastecimentos e manutenções e pode ser repetido. `smoke-publico.sh` aquece os serviços (repete só GET e login durante a partida a frio), exercita frontend, AsyncAPI, login, CRUD de veículo, abastecimento, `/aggregated-data` com as três fontes, dashboard, Swagger via APIM e CORS e, com o `az` logado, confere que não há PostgreSQL, ACR nem DNS privado e que o SQL exige TLS 1.2. `seed-demo.sh` usa `date -d`, do GNU: no macOS, instale o `coreutils` e ponha o `gnubin` dele no `PATH`. Em 11/11/2026, o smoke a frio passou com 28/28 verificações.

**Partida a frio:** com `minReplicas: 0` e o SQL serverless pausado, a primeira chamada depois de um tempo parado pode receber 502/503/504 por cerca de 1 a 2 min (o login levou ~90 s no smoke a frio). Aqueça antes de uma demonstração; o próprio `smoke-publico.sh` faz isso. Um POST que recebe 503 nessa janela pode ter sido gravado (ADR 0044).

### 8.9 Exclusão dos recursos da v0.30.0

O modo incremental não apaga nada. Depois do smoke verde, liste e exclua o que sobrou da v0.30.0 (os nomes têm o sufixo do ambiente):

```bash
az postgres flexible-server list -g "$RG" --query '[].name' -o tsv
az acr list -g "$RG" --query '[].name' -o tsv
az network private-dns zone list -g "$RG" --query '[].name' -o tsv
az containerapp job list -g "$RG" --query '[].name' -o tsv

az postgres flexible-server delete -g "$RG" -n <servidor> --yes
az acr delete -g "$RG" -n <registry> --yes
az network private-dns link vnet list -g "$RG" -z privatelink.postgres.database.azure.com --query '[].name' -o tsv
az network private-dns link vnet delete -g "$RG" -z privatelink.postgres.database.azure.com -n <link> --yes
az network private-dns zone delete -g "$RG" -n privatelink.postgres.database.azure.com --yes
az containerapp job delete -g "$RG" -n <job> --yes
```

Por fim, reimplante a fase B com `legacyPostgresqlSubnetEnabled=false` para remover a sub-rede `postgresql`. `scripts/smoke-publico.sh` volta a conferir o inventário.

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

Enquanto o PostgreSQL, o ACR e a zona DNS privada da v0.30.0 existirem, eles continuam cobrando: exclua-os assim que a v1.0.0 passar no smoke (seção 8.9).

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
