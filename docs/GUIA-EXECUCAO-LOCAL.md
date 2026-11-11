# Guia de execução local do NexFleet

Para preparar a homologação sem criar recursos, consulte também o [guia de pré-publicação Azure](GUIA-PRE-PUBLICACAO-AZURE.md).

Este guia explica como preparar, iniciar, acessar, testar e parar o NexFleet no Windows. Os comandos devem ser executados no PowerShell a partir da raiz do projeto. No MacBook, use o [guia específico para macOS](GUIA-EXECUCAO-MACOS.md).

Para entender a responsabilidade de cada pasta e o fluxo interno das requisições, consulte o [Guia de estrutura e arquitetura](GUIA-ESTRUTURA-PROJETO.md).

## 1. Visão geral

O ambiente local possui duas partes:

- **backend e infraestrutura**, executados pelo Docker Compose;
- **frontend**, executado pelo Vite em quatro terminais.

O navegador acessa somente o shell em `http://127.0.0.1:5173`. O shell e os microfrontends chamam o API Gateway em `http://127.0.0.1:8080`; eles nunca devem acessar os bancos diretamente.

## 2. Pré-requisitos

Antes de começar, confirme que possui:

1. Windows PowerShell 5.1 ou PowerShell 7;
2. Docker Desktop iniciado e usando contêineres Linux;
3. VS Code;
4. conexão com a internet na primeira instalação;
5. pgAdmin ou DBeaver apenas se quiser uma interface gráfica para o PostgreSQL.

Node.js 24 e JDK 21 não precisam ser instalados globalmente. O projeto mantém cópias portáteis em `.tools`.

Verifique o Docker:

```powershell
docker version
docker info
```

Os dois comandos devem mostrar informações do cliente e do servidor Docker.

## 3. Entrar na pasta correta

Abra o PowerShell e execute:

```powershell
cd "C:\Users\vinig\Downloads\Nova pasta\NexFleet-v0.14.0"
```

Confirme a pasta:

```powershell
Get-Location
Test-Path ".\scripts\Start-Local.ps1"
```

O segundo comando deve retornar `True`.

## 4. Instalar as dependências

Esta etapa é necessária na primeira preparação do projeto ou depois de uma alteração relevante nas dependências:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Install-Dependencies.ps1"
```

O script baixa Node.js 24 e JDK 21 portáteis, executa `npm ci` no shell e nos microfrontends, prepara o cache Maven e baixa imagens Docker quando possível.

## 5. Inicializar a configuração local

Execute uma vez:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Initialize-Local.ps1"
```

O script cria ou completa:

- `.env.sprint0`, com configurações e segredos locais;
- `.secrets/identidade-jwt.pem`, com a chave privada RSA local.

Abra `.env.sprint0` e substitua o marcador de `LOCAL_USER_PASSWORD` por uma senha local forte. Não publique, envie ou faça commit de `.env.sprint0` e `.secrets`.

As credenciais de login da aplicação são os valores destas variáveis:

```text
LOCAL_USER_EMAIL
LOCAL_USER_PASSWORD
```

As senhas dos bancos são separadas da senha de login.

## 6. Primeira subida do backend

Na primeira execução, crie o usuário administrativo local:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Start-Local.ps1" -ProvisionUser
```

O processo pode demorar na primeira vez porque o Docker precisa construir imagens e baixar dependências. O script aguarda os serviços e executa verificações de integração, eventos e métricas.

O provisionamento do usuário deve ser feito somente na primeira execução ou quando o volume do banco de Identidade for recriado.

## 7. Subidas seguintes do backend

Nas execuções normais:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Start-Local.ps1"
```

Quando as imagens já foram construídas e nenhum código Java ou Dockerfile mudou, é possível iniciar sem reconstruí-las:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Start-Local.ps1" -NoBuild
```

Confira os contêineres:

```powershell
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

Principais endereços:

| Recurso | Endereço |
|---|---|
| API Gateway | `http://127.0.0.1:8080` |
| RabbitMQ Management | `http://127.0.0.1:15672` |
| Prometheus | `http://127.0.0.1:9090` |

O usuário e a senha do RabbitMQ estão em `RABBITMQ_USER` e `RABBITMQ_PASSWORD` no `.env.sprint0`.

## 8. Subir o frontend

O frontend possui um shell e três microfrontends. Abra quatro terminais no VS Code.

Em **cada terminal**, comece na raiz do projeto e ative o toolchain:

```powershell
cd "C:\Users\vinig\Downloads\Nova pasta\NexFleet-v0.14.0"
Set-ExecutionPolicy -Scope Process Bypass -Force
. .\scripts\Use-Local-Toolchain.ps1
```

### Terminal 1 — shell

```powershell
cd frontend
npm.cmd run dev
```

### Terminal 2 — Frota

```powershell
cd microfrontends/frota
npm.cmd run dev
```

### Terminal 3 — Operações

```powershell
cd microfrontends/operacoes
npm.cmd run dev
```

### Terminal 4 — Painel

```powershell
cd microfrontends/painel
npm.cmd run dev
```

| Interface | Porta |
|---|---:|
| Shell | 5173 |
| Frota | 5174 |
| Operações | 5175 |
| Painel | 5176 |

Acesse `http://127.0.0.1:5173` e entre com `LOCAL_USER_EMAIL` e `LOCAL_USER_PASSWORD` do `.env.sprint0`.

## 9. Bancos de dados

Para entender autenticação, acesso `trust`, conexão com senha e rotação segura, consulte o [Guia de segurança dos bancos locais](GUIA-SEGURANCA-BANCO-LOCAL.md).

O NexFleet utiliza um banco PostgreSQL separado para cada domínio:

| Domínio | Contêiner | Banco/usuário | Schema | Variável da senha |
|---|---|---|---|---|
| Identidade | `nexfleet-sprint0-identidade-db-1` | `identidade` | `identidade` | `IDENTIDADE_DB_PASSWORD` |
| Frota | `nexfleet-sprint0-frota-db-1` | `frota` | `frota` | `FROTA_DB_PASSWORD` |
| Operações | `nexfleet-sprint0-operacoes-db-1` | `operacoes` | `operacoes` | `OPERACOES_DB_PASSWORD` |
| Indicadores | `nexfleet-sprint0-indicadores-db-1` | `indicadores` | `indicadores` | `INDICADORES_DB_PASSWORD` |
| Notificações | `nexfleet-sprint0-notificacoes-db-1` | `notificacoes` | `notificacoes` | `NOTIFICACOES_DB_PASSWORD` |

O PostgreSQL instalado diretamente no Windows é outra instância. Os dados do NexFleet ficam nos contêineres e volumes Docker.

### 9.1. Acessar pelo PowerShell

```powershell
# Frota
docker exec -it nexfleet-sprint0-frota-db-1 psql -U frota -d frota

# Identidade
docker exec -it nexfleet-sprint0-identidade-db-1 psql -U identidade -d identidade

# Operações
docker exec -it nexfleet-sprint0-operacoes-db-1 psql -U operacoes -d operacoes

# Indicadores
docker exec -it nexfleet-sprint0-indicadores-db-1 psql -U indicadores -d indicadores

# Notificações
docker exec -it nexfleet-sprint0-notificacoes-db-1 psql -U notificacoes -d notificacoes
```

O acesso pelo socket interno do contêiner não solicita senha. Quem possui permissão para usar `docker exec` já possui controle administrativo sobre o contêiner.

Para testar a autenticação por senha via TCP, use `-h` e `-W`. Exemplo de Frota:

```powershell
docker exec -it nexfleet-sprint0-frota-db-1 psql -h frota-db -U frota -d frota -W
```

Quando aparecer `Password:`, digite o valor de `FROTA_DB_PASSWORD`. A senha não aparece durante a digitação.

### 9.2. Comandos básicos do `psql`

Depois de entrar e aparecer `frota=#`:

```sql
\conninfo
SET search_path TO frota;
\dt
\d veiculo
SELECT id, placa, marca, modelo, ano, status, quilometragem
FROM veiculo
ORDER BY criado_em DESC;
```

Para sair:

```sql
\q
```

Consultas somente de leitura:

```sql
SELECT id, nome, cpf, cnh, status
FROM frota.motorista
ORDER BY criado_em DESC;

SELECT *
FROM operacoes.abastecimento
ORDER BY realizado_em DESC;

SELECT *
FROM operacoes.manutencao
ORDER BY realizada_em DESC;

SELECT id, email, perfil, ativo
FROM identidade.usuario
ORDER BY email;
```

Evite `UPDATE`, `DELETE`, `TRUNCATE` e `DROP` diretamente. Cadastros devem ser feitos pela interface ou API para que validações, autorização, auditoria, outbox e eventos sejam executados corretamente.

### 9.3. Acessar pelo pgAdmin ou DBeaver

O arquivo opcional `compose.db-access.yaml` publica os bancos somente em `127.0.0.1`, usando portas alternativas para não conflitar com um PostgreSQL instalado no Windows.

Com o backend iniciado, execute na raiz:

```powershell
docker compose `
  --env-file ".env.sprint0" `
  -f "compose.sprint0.yaml" `
  -f "compose.jwt-rsa.yaml" `
  -f "compose.db-access.yaml" `
  up -d --no-build
```

Cadastre cada conexão no pgAdmin em **Servers > Register > Server**:

| Banco | Host | Porta | Database | Username | Senha no `.env.sprint0` |
|---|---|---:|---|---|---|
| Identidade | `127.0.0.1` | 15432 | `identidade` | `identidade` | `IDENTIDADE_DB_PASSWORD` |
| Frota | `127.0.0.1` | 15433 | `frota` | `frota` | `FROTA_DB_PASSWORD` |
| Operações | `127.0.0.1` | 15434 | `operacoes` | `operacoes` | `OPERACOES_DB_PASSWORD` |
| Indicadores | `127.0.0.1` | 15435 | `indicadores` | `indicadores` | `INDICADORES_DB_PASSWORD` |
| Notificações | `127.0.0.1` | 15436 | `notificacoes` | `notificacoes` | `NOTIFICACOES_DB_PASSWORD` |

Para encontrar as tabelas no pgAdmin:

```text
Servers
└── NexFleet Frota
    └── Databases
        └── frota
            └── Schemas
                └── frota
                    └── Tables
```

Essas portas aceitam conexões somente do próprio computador. Não altere `127.0.0.1` para `0.0.0.0` em desenvolvimento.

## 10. Ver logs

Todos os serviços:

```powershell
docker compose `
  --env-file ".env.sprint0" `
  -f "compose.sprint0.yaml" `
  -f "compose.jwt-rsa.yaml" `
  logs --tail 100
```

Um serviço específico, acompanhando novas linhas:

```powershell
docker compose `
  --env-file ".env.sprint0" `
  -f "compose.sprint0.yaml" `
  -f "compose.jwt-rsa.yaml" `
  logs -f --tail 100 frota
```

Use `Ctrl+C` para sair dos logs; isso não para o contêiner.

### Localizar uma operação pelo identificador de correlação

Cada resposta da API contém `X-Correlation-ID`. Para criar um valor conhecido e localizar a mesma chamada nos serviços:

```powershell
$id = [guid]::NewGuid().ToString()
$resposta = Invoke-WebRequest `
  -UseBasicParsing `
  -Uri "http://127.0.0.1:8080/api/v1/ambiente" `
  -Headers @{ "X-Correlation-ID" = $id }

$resposta.Headers["X-Correlation-ID"]

docker compose `
  --env-file ".env.sprint0" `
  -f "compose.sprint0.yaml" `
  -f "compose.sprint1-local.yaml" `
  -f "compose.jwt-rsa.yaml" `
  logs --since 5m gateway bff identidade frota operacoes indicadores |
  Select-String -SimpleMatch $id
```

Pesquise pelo UUID, nunca pelo JWT, senha, CPF ou CNH. O fluxo completo é explicado na [Aula 20](tutorials/20-correlacao-ponta-a-ponta.md).

## 11. Executar os testes

```powershell
# Teste geral
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-Project.ps1"

# Teste geral sem reinstalar dependências JavaScript
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-Project.ps1" -SkipInstall

# CQ03/CQ04: PostgreSQL temporário, quilometragem regressiva e rollback integral
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-Cq03Cq04.ps1"

# CQ05: dois bancos temporários, inativação e preservação do histórico
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-Cq05.ps1"

# CQ07: banco indisponível, readiness e log seguro
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-Cq07.ps1"

# Teste geral incluindo as provas integradas CQ03/CQ04/CQ05/CQ07
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-Project.ps1" -SkipInstall -IncludeDatabaseIntegration

# Contratos HTTP reais, sem gravar dados de negócio
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-ApiContracts.ps1"

# Smoke E2E completo: APIs, filas, Function, DLQ e Prometheus
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-E2E.ps1"

# CQ09: 100 usuários simultâneos, listas paginadas e p95 abaixo de 2 segundos
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-Performance.ps1"

# E2E completo incluindo o CQ09
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-E2E.ps1" -IncludePerformance

# CQ10: backup temporário e restauração isolada dos cinco bancos
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-Recovery.ps1"

# E2E com desempenho e recuperação
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-E2E.ps1" -IncludePerformance -IncludeRecovery

# Testes específicos com o ambiente ativo
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-Sprint2Eda.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-Sprint3Serverless.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-Observability.ps1"
```

`Test-Project.ps1` também executa os contratos OpenAPI/AsyncAPI em `quality/`. `Test-ApiContracts.ps1` e `Test-Performance.ps1` leem `LOCAL_USER_EMAIL` e `LOCAL_USER_PASSWORD` do `.env.sprint0`, mas não imprimem esses valores. O E2E não cria dados de Frota ou Operações; o teste da Function grava somente uma notificação com UUID aleatório e envia uma mensagem inválida para a DLQ, como evidência controlada de idempotência e retry. O CQ09 é somente leitura e seus parâmetros podem ser ajustados com `-Users`, `-Iterations`, `-PageSize` e `-ThresholdMs`.

`Test-Recovery.ps1` cria cópias temporárias dos cinco bancos, restaura em contêineres isolados e compara as tabelas. Ele não substitui os bancos ativos e apaga os artefatos do ensaio ao terminar. Para manter um backup manual em `backups/<data-hora>`, use `Backup-Databases.ps1`; proteja esses arquivos porque contêm dados do sistema.

Os testes frontend incluídos em `Test-Project.ps1` também comprovam o CQ06: uma tentativa inválida mantém os campos corretos, marca os controles que precisam de correção e exibe uma mensagem acessível. Consulte a [Evidência CQ06](EVIDENCIA-CQ06-USABILIDADE.md) e a [matriz CQ01–CQ12](MATRIZ-CQ01-CQ12.md).

`Test-Cq03Cq04.ps1` não usa `.env.sprint0`: ele gera credenciais, porta e contêiner exclusivos, aplica as migrações de Operações e apaga o ambiente ao terminar. Portanto, pode ser executado com o NexFleet ativo sem alterar abastecimentos, hodômetros ou eventos existentes. Consulte a [Evidência CQ03/CQ04](EVIDENCIA-CQ03-CQ04-TRANSACAO.md).

`Test-Cq05.ps1` também não usa `.env.sprint0`. Ele cria bancos separados para Frota e Operações, executa a sequência criar/registrar/inativar/consultar e remove os dois contêineres. Consulte a [Evidência CQ05](EVIDENCIA-CQ05-HISTORICO.md).

`Test-Cq07.ps1` empacota Frota e cria serviço, banco e rede temporários. Ele para somente o banco criado pelo próprio ensaio, verifica readiness/API `DOWN/503`, inspeciona correlação e reprova se as sentinelas de senha ou token aparecerem no log. Consulte a [Evidência CQ07](EVIDENCIA-CQ07-INDISPONIBILIDADE.md).

Para executar o E2E sem a prova serverless ou sem o Prometheus:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-E2E.ps1" -SkipServerless
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-E2E.ps1" -SkipObservability
```

## 12. Parar o projeto

Nos quatro terminais do frontend, pressione `Ctrl+C`.

Depois, na raiz do projeto:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Stop-Local.ps1"
```

Esse comando para os contêineres, mas preserva os volumes e os dados dos bancos.

Não execute `docker compose down -v` a menos que queira apagar permanentemente todos os dados locais do NexFleet.

## 13. Rotina diária resumida

1. Inicie o Docker Desktop.
2. Entre na raiz do projeto.
3. Execute `Start-Local.ps1 -NoBuild`.
4. Abra quatro terminais e ative `Use-Local-Toolchain.ps1` em cada um.
5. Inicie shell, Frota, Operações e Painel com `npm.cmd run dev`.
6. Acesse `http://127.0.0.1:5173`.
7. Ao terminar, use `Ctrl+C` nos frontends e execute `Stop-Local.ps1`.

## 14. Solução de problemas

### O PowerShell mostra `>>`

O PowerShell está esperando o restante de um comando incompleto. Pressione `Ctrl+C` e execute o comando novamente. Em comandos de várias linhas, o caractere de continuação `` ` `` deve ser o último caractere da linha.

### O terminal está em `C:\Windows\System32`

```powershell
cd "C:\Users\vinig\Downloads\Nova pasta\NexFleet-v0.14.0"
```

### Execução de scripts desabilitada

Use `powershell.exe -NoProfile -ExecutionPolicy Bypass -File` como mostrado neste guia. O bypass fica limitado ao novo processo.

### Docker Desktop não está disponível

Abra o Docker Desktop, aguarde **Engine running** e execute `docker info`.

### A tela abre, mas algum microfrontend não carrega

Confirme as quatro portas:

```powershell
Get-NetTCPConnection -State Listen | Where-Object LocalPort -In 5173,5174,5175,5176
```

### Erro 401 ou sessão expirada

Entre novamente usando `LOCAL_USER_EMAIL` e `LOCAL_USER_PASSWORD`. Não use as senhas dos bancos na tela de login.

### pgAdmin mostra `connection refused`

1. Confirme que o banco está ativo com `docker ps`.
2. Execute o comando da seção 9.3 com `compose.db-access.yaml`.
3. Use host `127.0.0.1`, não `frota-db`.
4. Use a porta alternativa correta, por exemplo 15433 para Frota.
5. Use a senha correspondente do `.env.sprint0`.

### O veículo salvo não aparece

Clique em **Atualizar lista**, remova filtros e confira a página atual. Cadastros feitos diretamente no banco não atualizam outras sessões do navegador em tempo real.

### Verificar portas ocupadas

```powershell
Get-NetTCPConnection -State Listen |
  Where-Object LocalPort -In 8080,9090,15672,5173,5174,5175,5176,15432,15433,15434,15435,15436 |
  Sort-Object LocalPort
```

## Preparação Azure

A execução local não exige Azure. A infraestrutura Bicep e o ponto exato em que uma conta passa a ser necessária estão no [Guia da infraestrutura Azure com Bicep](GUIA-INFRAESTRUTURA-AZURE-BICEP.md). Não use comandos de deploy antes do preflight conectado e da revisão do `what-if`.
