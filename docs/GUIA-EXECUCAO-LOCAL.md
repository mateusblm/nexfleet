# Guia de execução local do NexFleet

Sobe o sistema inteiro (6 serviços Java, Azure Function, SQL Server, MongoDB, RabbitMQ e Azurite) a partir do repositório guarda-chuva, com as imagens do Docker Hub ou compilando os repositórios irmãos. Comandos em `bash` a partir da raiz do guarda-chuva (Linux, macOS ou WSL).

## 1. Pré-requisitos

- Docker com Compose v2 e ~6 GB de RAM livres (o SQL Server sozinho usa até 2 GB; cada serviço Java até 512 MB).
- `bash`, `curl`, `jq`, `openssl` e `git`.
- Node.js 24 para as telas (repositório `nexfleet-frontend`).

## 2. Preparar (uma vez)

```bash
scripts/iniciar-local.sh
```

- Cria `.env` a partir de `.env.example`, trocando cada `SUBSTITUA_*` por uma senha aleatória. Nunca sobrescreve um `.env` existente.
- Gera `.secrets/identidade-jwt.pem` (RSA 3072, PKCS#8) com `scripts/gerar-chave-jwt.sh`; uma chave existente nunca é substituída.
- Avisa se alguma porta publicada já está em uso. Troque-a no `.env` (`GATEWAY_PORT`, `SQLSERVER_PORT`, `MONGO_PORT`, `RABBITMQ_MGMT_PORT`, `FUNCTION_PORT`).

`.env` e `.secrets/` ficam fora do Git.

## 3. Subir

Imagens publicadas (`mateusblm/nexfleet-<svc>:${NEXFLEET_TAG}`):

```bash
docker compose up -d
```

Compilando a partir do código, com os repositórios lado a lado do guarda-chuva:

```bash
scripts/clonar-tudo.sh                                   # clona os 8 repositórios que faltam
docker compose -f compose.yaml -f compose.build.yaml up -d --build
```

Para compilar de outra pasta (por exemplo, worktrees), defina `NEXFLEET_REPOS_DIR` (padrão `..`).

Ordem de subida, garantida por `depends_on` com `condition`:

1. `sqlserver`, `mongodb`, `rabbitmq`, `azurite` (healthchecks).
2. `sqlserver-bootstrap` roda `infra/sqlserver/bootstrap.sql` com `sqlcmd` (banco, schemas e usuários; ver seção 6) e `rabbitmq-topology` declara a fila da Function.
3. `notificacoes-migracoes` aplica as migrações T-SQL da Function com a CLI do Flyway, lidas do jar dentro da imagem da Function.
4. `identidade` (perfil `jwt-rsa,local-seed`: cria o Administrador do `.env` se ele não existir), depois `frota`, `operacoes`, `indicadores` e `function`, depois `bff` e `gateway`.

A primeira subida leva alguns minutos. Acompanhe com `docker compose ps`; todos os serviços ficam `healthy` e os de execução única terminam com `Exited (0)`.

## 4. Dados de demonstração

```bash
scripts/seed-demo.sh
```

Pela API pública do Gateway: login do Administrador, 5 veículos, 5 motoristas, um vínculo por veículo, 15 abastecimentos (quilometragem crescente) e 6 manutenções (datas passadas variadas). Rodar de novo não duplica nada: 409 é ignorado e veículos que já têm abastecimentos ou manutenções são pulados.

Contra outro ambiente: `NEXFLEET_API=https://<gateway> NEXFLEET_EMAIL=... NEXFLEET_SENHA=... scripts/seed-demo.sh`.

Abastecimentos exigem vínculo vigente no instante informado, e o vínculo começa no momento da criação; por isso os abastecimentos do seed têm o instante atual.

## 5. Endereços

| Endereço | Uso |
|---|---|
| `http://127.0.0.1:${GATEWAY_PORT}` | API pública (Gateway) |
| `http://127.0.0.1:${GATEWAY_PORT}/swagger-ui.html` | Swagger UI com BFF, Frota, Operações, Identidade e Indicadores |
| `http://127.0.0.1:${GATEWAY_PORT}/aggregated-data` | Visão consolidada (com token) |
| `http://127.0.0.1:${RABBITMQ_MGMT_PORT}` | RabbitMQ (`RABBITMQ_USER` / `RABBITMQ_PASSWORD`) |
| `127.0.0.1:${SQLSERVER_PORT}` | SQL Server (banco `nexfleet`; logins na seção 6) |
| `127.0.0.1:${MONGO_PORT}` | MongoDB da Frota (`MONGO_ROOT_USER` / `MONGO_ROOT_PASSWORD`) |
| `http://127.0.0.1:${FUNCTION_PORT}/api/calcular-eficiencia` | Function HTTP (cabeçalho `x-functions-key`) |

## 6. Banco SQL Server: schema e usuário por serviço

`infra/sqlserver/bootstrap.sql` é idempotente e roda a cada `up`:

- No SQL Server local (não no Azure SQL Database), habilita `contained database authentication`, cria o banco `nexfleet` e o deixa com `CONTAINMENT = PARTIAL`.
- Para cada serviço (`identidade`, `operacoes`, `indicadores`, `notificacoes`), cria um **usuário contido** (`CREATE USER x WITH PASSWORD`; se já existir, a senha é sincronizada com o `.env`), o schema de mesmo nome **pertencente a esse usuário** e concede `CREATE TABLE` e `CREATE VIEW`. Nada é concedido em outro schema.
- O schema pertence ao serviço, e não a `dbo`, para não haver encadeamento de propriedade: com todos os schemas de `dbo`, um serviço poderia criar no próprio schema uma view sobre outro schema e lê-lo.
- Os serviços usam `spring.flyway.create-schemas=false`: quem cria o schema é o bootstrap.

O mesmo script serve no Azure SQL Database, que não tem `CREATE LOGIN` no banco de usuário. Rode-o conectado ao banco `nexfleet` com o administrador do servidor:

```bash
NEXFLEET_DB=nexfleet IDENTIDADE_DB_PASSWORD=... OPERACOES_DB_PASSWORD=... \
INDICADORES_DB_PASSWORD=... NOTIFICACOES_DB_PASSWORD=... \
sqlcmd -S <servidor>.database.windows.net -d nexfleet -U <admin> -b -i infra/sqlserver/bootstrap.sql
```

As senhas são interpoladas como texto pelo `sqlcmd`: não use aspas simples nelas.

Conferir o isolamento:

```bash
set -a; . ./.env; set +a
docker compose exec -e PW="$OPERACOES_DB_PASSWORD" sqlserver bash -c \
  '/opt/mssql-tools18/bin/sqlcmd -S localhost -d nexfleet -U operacoes -P "$PW" -C -Q "SELECT TOP 1 email FROM identidade.usuario"'
# Msg 229: The SELECT permission was denied on the object 'usuario', ... schema 'identidade'.
```

## 7. Function local e chave do gatilho HTTP

O gatilho `CalcularEficiencia` usa `authLevel = FUNCTION`: sem chave, o host responde 401. Localmente o contêiner `function` usa `AzureWebJobsSecretStorageType=files` e `infra/function/iniciar-com-chaves.sh` escreve `/azure-functions-host/Secrets/host.json` antes de iniciar o host, com:

- `EFICIENCIA_FUNCTION_KEY` como chave de host (`functionKeys.default`), válida para qualquer função; o BFF a envia em `x-functions-key`;
- `FUNCTION_MASTER_KEY` como chave mestra.

O BFF chama `EFICIENCIA_FUNCTION_URL` (local: `http://function:80`). Na Azure as chaves ficam no armazenamento da Function App e o script não é usado. O gatilho RabbitMQ da notificação continua ativo localmente (fila `nexfleet.notificacoes.abastecimentos.v1`); o de Service Bus fica desabilitado.

## 8. Telas

No repositório `nexfleet-frontend`, um terminal por pasta (`npm ci` na primeira vez):

```bash
cd frontend && NEXFLEET_GATEWAY_URL=http://127.0.0.1:${GATEWAY_PORT} npm run dev   # 5173
cd microfrontends/frota && npm run dev       # 5174
cd microfrontends/operacoes && npm run dev   # 5175
cd microfrontends/painel && npm run dev      # 5176
```

O shell encaminha `/api` ao Gateway (`NEXFLEET_GATEWAY_URL`, padrão `http://127.0.0.1:8080`). A página dos eventos (`/docs/eventos/`) é estática: no `npm run dev` abra `/docs/eventos/index.html`; com `npm run build && npx vite preview` ela responde em `/docs/eventos/`.

## 9. Logs, parar e limpar

```bash
docker compose logs -f bff                 # um serviço
docker compose down                        # para; dados preservados nos volumes
docker compose down -v                     # apaga também SQL Server, MongoDB, RabbitMQ e Azurite
```

## 10. Problemas comuns

- **`sqlserver-bootstrap` falha com "password does not meet ... policy"**: a senha precisa de 8+ caracteres com maiúscula, minúscula e dígito e não pode conter o nome do usuário. O `iniciar-local.sh` já gera senhas válidas.
- **Trocou `MSSQL_SA_PASSWORD` depois da primeira subida**: o volume guarda a senha antiga; volte a anterior ou rode `docker compose down -v`.
- **MongoDB não sobe com `mongo:8` em kernel Linux 6.19+** (SERVER-121912): mantenha `MONGO_IMAGE=mongo:7.0`.
- **Porta ocupada**: troque a porta no `.env` e, para as telas, passe a nova porta do Gateway em `NEXFLEET_GATEWAY_URL`.
- **Pouca memória**: reduza `JAVA_MEM_LIMIT` (mínimo prático ~384m) ou `MSSQL_MEMORY_LIMIT_MB`.
