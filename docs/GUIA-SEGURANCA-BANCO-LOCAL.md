# Guia de segurança e acesso aos bancos (local e Azure)

## Objetivo

Este guia cobre dois ambientes:

- **Local (seções 1 a 6):** por que alguns comandos entram no PostgreSQL sem pedir senha, como exigir autenticação TCP, como trocar uma senha e quais limites de segurança existem num ambiente Docker de desenvolvimento.
- **Azure (seção 7):** como consultar os bancos da homologação na nuvem.

Não copie para documentação, Git, chat ou captura de tela os valores de `.env.sprint0`.

## 1. Por que `docker exec` pode não pedir senha

O comando abaixo inicia o `psql` dentro do próprio contêiner do PostgreSQL:

```powershell
docker exec -it nexfleet-sprint0-frota-db-1 psql -U frota -d frota
```

Essa conexão pode usar o socket Unix interno e a regra local `trust` da imagem. Isso não significa que o banco esteja publicado sem senha na rede. Quem consegue executar `docker exec` já controla o Docker e, na prática, possui acesso administrativo aos contêineres.

As proteções principais nesse cenário são:

- conta do Windows bloqueada por senha;
- Docker Desktop acessível somente ao usuário autorizado;
- bancos sem porta publicada por padrão;
- redes Docker de dados marcadas como internas;
- senhas aleatórias no `.env.sprint0` ignorado pelo Git.

## 2. Entrar exigindo a senha

Para forçar uma conexão TCP dentro da rede Docker, informe o host e use `-W`:

```powershell
docker exec -it nexfleet-sprint0-frota-db-1 `
  psql -h frota-db -U frota -d frota -W
```

Quando aparecer `Password:`, digite o valor de `FROTA_DB_PASSWORD` do `.env.sprint0`. Nenhum caractere aparece durante a digitação; isso é normal.

Para os outros bancos, use a correspondência:

| Serviço | Host/contêiner | Usuário e banco | Variável local |
|---|---|---|---|
| Identidade | `identidade-db` | `identidade` | `IDENTIDADE_DB_PASSWORD` |
| Frota | `frota-db` | `frota` | `FROTA_DB_PASSWORD` |
| Operações | `operacoes-db` | `operacoes` | `OPERACOES_DB_PASSWORD` |
| Indicadores | `indicadores-db` | `indicadores` | `INDICADORES_DB_PASSWORD` |
| Notificações | `notificacoes-db` | `notificacoes` | `NOTIFICACOES_DB_PASSWORD` |

## 3. Acessar por pgAdmin ou DBeaver

Os bancos não possuem porta no Windows por padrão. Para estudo local, use o override restrito ao loopback:

```powershell
docker compose `
  --env-file ".env.sprint0" `
  -f "compose.sprint0.yaml" `
  -f "compose.jwt-rsa.yaml" `
  -f "compose.db-access.yaml" `
  up -d
```

Consulte as portas definidas em [`compose.db-access.yaml`](../compose.db-access.yaml) e conecte ao host `127.0.0.1`, nunca a `0.0.0.0`. Use o usuário, banco e senha correspondentes.

Quando terminar o acesso gráfico, retorne ao Compose normal:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\scripts\Start-Local.ps1" -NoBuild
```

## 4. Trocar a senha de Frota

Entre no banco pelo acesso administrativo local:

```powershell
docker exec -it nexfleet-sprint0-frota-db-1 psql -U frota -d frota
```

No prompt `frota=#`, execute:

```sql
\password frota
```

Digite a nova senha duas vezes. Esse comando é preferível a escrever a senha em um `ALTER ROLE`, pois evita deixá-la visível no histórico do terminal.

Depois:

1. atualize somente `FROTA_DB_PASSWORD` em `.env.sprint0`;
2. não altere outras credenciais;
3. recrie o banco e o serviço Frota sem remover o volume:

```powershell
docker compose `
  --env-file ".env.sprint0" `
  -f "compose.sprint0.yaml" `
  -f "compose.jwt-rsa.yaml" `
  up -d --no-build --force-recreate frota-db frota
```

Teste a nova senha:

```powershell
docker exec -it nexfleet-sprint0-frota-db-1 `
  psql -h frota-db -U frota -d frota -W
```

O mesmo processo vale para os outros bancos, trocando serviço, usuário e variável.

## 5. Cuidados importantes

- Não execute `docker compose down -v` para trocar senha; `-v` apaga os volumes e os dados.
- Não coloque senha na linha de comando, URL, código-fonte ou documentação.
- Não altere `pg_hba.conf` para aceitar conexões externas amplas em um notebook de desenvolvimento.
- Não publique portas de banco em todas as interfaces de rede.
- A senha do PostgreSQL é diferente da senha usada no login web do NexFleet.
- Em produção, use cofre de segredos, TLS, contas com privilégio mínimo, auditoria, backup testado e rota de administração privada.

## 6. Sair do `psql`

No prompt do PostgreSQL:

```sql
\q
```

Para comandos de consulta e explicação dos schemas, consulte o [Guia de execução local](GUIA-EXECUCAO-LOCAL.md).

## 7. Acessar o banco na nuvem (Azure)

### 7.1 Por que não dá para conectar direto

Na Azure, os 5 bancos ficam num único **PostgreSQL Flexible Server privado** (`psql-nexfleet-homolog-...`), dentro de uma rede virtual (VNet).

- O servidor **não tem endereço público**. O seu PC, o pgAdmin, o DBeaver e o Portal da Azure não conseguem se conectar a ele.
- Isso é proposital: só os serviços que rodam dentro da rede da Azure enxergam o banco.
- As senhas dos bancos ficam guardadas como segredos dos Container Apps e dos jobs. **Você não precisa delas.**

Para consultar, o projeto usa o script `scripts/Invoke-AzureDatabaseQuery.ps1`. Ele faz o seguinte:

1. Inicia o job `job-nexfleet-db-verify`, que roda **dentro da rede da Azure**, com o seu SQL.
2. O job conecta com o usuário **do próprio banco** (`nexfleet_frota`, `nexfleet_operacoes` etc.), nunca com o administrador do servidor.
3. A sessão abre em **modo somente leitura** (`default_transaction_read_only=on`) e com limite de 30 s por comando.
4. O resultado volta pelos logs (Log Analytics) e aparece no seu terminal em **1 a 3 minutos**.

### 7.2 Pré-requisitos (uma vez por terminal)

| Requisito | Por quê |
|---|---|
| Azure CLI com login feito | O script usa a sua conta para iniciar o job e ler os logs |
| `infra/azure/preflight-profile.json` | Contém a assinatura e o grupo de recursos. Existe só no PC de quem fez o deploy e é ignorado pelo Git |

No terminal do VS Code (**Ctrl + '**), dentro da pasta do projeto:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
az account show -o table      # se der erro, rode: az login
```

### 7.3 Passo a passo: ver um veículo cadastrado

1. Cadastre o veículo pelo site.
2. Rode a consulta:

   ```powershell
   ./scripts/Invoke-AzureDatabaseQuery.ps1 -Database frota `
     -Sql "SELECT placa, marca, modelo, ano, tipo, quilometragem, status, criado_em FROM frota.veiculo ORDER BY criado_em DESC"
   ```

3. Acompanhe as mensagens:

   ```text
   Consulta enviada (job-nexfleet-db-verify-xxxx). Aguardando a execucao dentro da VNet...
   Execucao: Succeeded. Lendo o resultado no Log Analytics (pode levar alguns minutos)...
     placa  | marca | modelo | ano  | tipo | quilometragem |   status   |  criado_em
   ---------+-------+--------+------+------+---------------+------------+------------
    YLN2622 | Audi  | Rs6    | 2026 | SUV  |             0 | INATIVO    | 2026-11-11 ...
   (1 row)
   ```

**Buscar um veículo pela placa:**

```powershell
./scripts/Invoke-AzureDatabaseQuery.ps1 -Database frota `
  -Sql "SELECT * FROM frota.veiculo WHERE placa = 'YLN2622'"
```

### 7.4 Onde fica cada dado

O parâmetro `-Database` escolhe o banco. Use sempre o nome completo `schema.tabela`.

| `-Database` | Tabelas | O que guardam |
|---|---|---|
| `identidade` | `identidade.usuario` | Contas de acesso: e-mail, perfil, ativo. Nunca selecione `senha_hash` |
| `frota` | `frota.veiculo`, `frota.motorista`, `frota.veiculo_motorista` | Veículos, motoristas e vínculos |
| `operacoes` | `operacoes.abastecimento`, `operacoes.manutencao`, `operacoes.hodometro`, `operacoes.outbox_evento` | Abastecimentos, manutenções, último km de cada veículo e eventos publicados |
| `indicadores` | `indicadores.abastecimento_projecao`, `indicadores.manutencao_projecao` | Dados do Painel, montados a partir dos eventos |
| `notificacoes` | `notificacoes.email_capturado` | E-mails registrados pela Function |

### 7.5 Consultas úteis

```powershell
# Listar as tabelas de um banco
./scripts/Invoke-AzureDatabaseQuery.ps1 -Database frota `
  -Sql "SELECT table_name FROM information_schema.tables WHERE table_schema = 'frota' ORDER BY 1"

# Ver as colunas de uma tabela
./scripts/Invoke-AzureDatabaseQuery.ps1 -Database frota `
  -Sql "SELECT column_name, data_type FROM information_schema.columns WHERE table_schema = 'frota' AND table_name = 'veiculo' ORDER BY ordinal_position"

# Motoristas (CPF e CNH são dados pessoais: mostre só o necessário)
./scripts/Invoke-AzureDatabaseQuery.ps1 -Database frota `
  -Sql "SELECT nome, categoria, validade_cnh, status FROM frota.motorista ORDER BY nome"

# Abastecimentos mais recentes
./scripts/Invoke-AzureDatabaseQuery.ps1 -Database operacoes `
  -Sql "SELECT veiculo_id, realizado_em, combustivel, litros, valor_total, quilometragem FROM operacoes.abastecimento ORDER BY realizado_em DESC LIMIT 20"

# Contas de acesso (sem a senha)
./scripts/Invoke-AzureDatabaseQuery.ps1 -Database identidade `
  -Sql "SELECT email, perfil, ativo FROM identidade.usuario ORDER BY email"

# Migrações aplicadas (Flyway)
./scripts/Invoke-AzureDatabaseQuery.ps1 -Database frota `
  -Sql "SELECT version, description, success FROM frota.flyway_schema_history ORDER BY installed_rank"
```

> Os bancos são separados por serviço. Não dá para fazer `JOIN` entre `frota.veiculo` e `operacoes.abastecimento` numa única consulta. Para saber a placa de um abastecimento, consulte o `veiculo_id` em Operações e depois busque esse id em Frota.

### 7.6 Alterar dados (com cuidado)

O padrão é **somente leitura**: um `INSERT`, `UPDATE` ou `DELETE` falha com `cannot execute ... in a read-only transaction`.

Para alterar, inclua `-PermitirEscrita`. O script mostra o comando em amarelo e só continua se você digitar **`CONFIRMAR`**:

```powershell
./scripts/Invoke-AzureDatabaseQuery.ps1 -Database frota -PermitirEscrita `
  -Sql "UPDATE frota.veiculo SET status = 'DISPONIVEL' WHERE placa = 'YLN2622' RETURNING placa, status"
```

- **Prefira o site.** Cadastrar, editar, inativar, reativar e excluir pela tela aplica as regras do sistema (validações, histórico, eventos). Uma alteração direta no banco pula essas regras.
- **Rode antes um `SELECT`** com o mesmo `WHERE`, para conferir o que será afetado.
- **Nunca rode `UPDATE` ou `DELETE` sem `WHERE`.**
- **Não há como desfazer.** A única recuperação é a restauração do backup (CQ10, até 7 dias atrás).

Exemplos prontos para contas e senhas estão no [Guia de administração da Azure](GUIA-ADMINISTRACAO-AZURE.md).

### 7.7 Ver o servidor no Portal da Azure

O Portal mostra o **servidor**, mas não os dados:

1. Entre em https://portal.azure.com e abra o grupo `rg-nexfleet-homolog`.
2. Abra o servidor `psql-nexfleet-homolog-...` (tipo *Servidor flexível do Azure Database for PostgreSQL*).
3. Itens úteis:
   - **Visão geral:** status, versão e região;
   - **Bancos de dados:** os 5 bancos;
   - **Rede:** acesso privado pela VNet, sem acesso público;
   - **Métricas:** CPU, conexões e armazenamento;
   - **Backup e restauração:** pontos de restauração (CQ10).

### 7.8 Problemas comuns

| Sintoma | Causa | Solução |
|---|---|---|
| `Please run 'az login'` | Sessão da Azure expirada | `az login` |
| `ConnectionResetError 10054` | Instabilidade de rede | O script repete sozinho; se falhar de vez, rode de novo |
| `relation "veiculo" does not exist` | Faltou o schema | Use `frota.veiculo`, não só `veiculo` |
| `relation "operacoes.abastecimento" does not exist` (ou `schema ... does not exist`) | Tabela de outro banco: o `-Database` está errado | Use o `-Database` da tabela (seção 7.4). Cada usuário só acessa o próprio banco |
| `A consulta falhou; veja a mensagem do PostgreSQL acima` | Erro no SQL | Role a tela para cima: a linha `ERROR:` explica o motivo |
| `cannot execute ... read-only transaction` | Alteração sem `-PermitirEscrita` | Inclua a opção, ou faça a alteração pelo site |
| O resultado demora mais de 3 min | Os logs da Azure às vezes atrasam | Aguarde. O script espera até cerca de 5 min antes de desistir |
| `preflight-profile.json` não encontrado | Você está em outro PC | O acesso à nuvem só funciona no PC que tem esse arquivo |
