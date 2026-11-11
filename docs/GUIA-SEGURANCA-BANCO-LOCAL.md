# Guia de segurança dos bancos locais

## Objetivo

Este guia explica por que alguns comandos locais entram no PostgreSQL sem pedir senha, como exigir autenticação TCP, como trocar uma senha e quais limites de segurança existem em um ambiente Docker de desenvolvimento.

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
