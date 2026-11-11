# ADR 0040 — Azure SQL com um schema e um usuário contido por serviço

Data: 11/11/2026
Estado: aceita

## Contexto

O enunciado final exige um microsserviço com **Azure SQL**. Até a v0.30.0, Identidade, Operações, Indicadores e a Function de notificação usavam bancos PostgreSQL separados (local) e um PostgreSQL Flexible Server privado com cinco bancos (Azure), migrados por um job dentro da VNet (ADR 0037). Esse servidor era o maior custo fixo da homologação.

O Azure SQL Database tem uma oferta gratuita serverless, mas apenas **um banco gratuito por assinatura**. Manter um banco por serviço significaria pagar por três deles.

## Decisão

1. **Um banco, um schema por serviço.** Um único Azure SQL Database (`nexfleet`) com os schemas `identidade`, `operacoes`, `indicadores` e `notificacoes`. Localmente, o mesmo desenho roda em `mcr.microsoft.com/mssql/server:2022-latest` no Compose; os testes de integração usam Testcontainers com SQL Server 2022.
2. **Um usuário contido por serviço, com o nome do schema.** Os usuários são `identidade`, `operacoes`, `indicadores` e `notificacoes` (`CREATE USER ... WITH PASSWORD`, porque o Azure SQL Database não tem `CREATE LOGIN` no banco de usuário). Cada schema pertence ao usuário do próprio serviço (`ALTER AUTHORIZATION`), que recebe também `CREATE TABLE` e `CREATE VIEW` no banco. Nenhum usuário recebe permissão em outro schema. Como os objetos de cada schema pertencem ao serviço, não há encadeamento de propriedade que permita ler outro schema por uma view.
3. **Bootstrap pelo administrador.** `infra/sqlserver/bootstrap.sql` é idempotente e roda com `sqlcmd` pelo administrador do servidor: cria (ou sincroniza a senha de) cada usuário e cria os schemas. No SQL Server local ele também habilita a autenticação de banco contido e deixa o banco com `CONTAINMENT = PARTIAL`. O mesmo script serve ao Compose (serviço `sqlserver-bootstrap`) e à Azure.
4. **Flyway recomeçado em V1 por serviço.** Não há migração de dados (começo limpo): cada serviço tem uma única `V1__*.sql` em T-SQL (`UNIQUEIDENTIFIER`, `DATETIMEOFFSET(6)`, `NVARCHAR(MAX)` com `ISJSON` no lugar de `jsonb`). Nos adaptadores, `INSERT ... ON CONFLICT` virou inserção condicional (`NOT EXISTS`/`MERGE`). Os serviços usam `spring.flyway.schemas=<schema>`, `default-schema=<schema>` e `create-schemas=false`: o schema já existe pelo bootstrap e o usuário do serviço não tem permissão para criar schemas. Identidade, Operações e Indicadores migram na subida. A Function não executa Flyway; localmente o Compose aplica a V1 de `notificacoes` com a imagem `flyway/flyway` lendo o jar da Function.
5. **Outbox no SQL Server.** `FOR UPDATE SKIP LOCKED` virou `WITH (INDEX(ix_outbox_pendente), UPDLOCK, READPAST, ROWLOCK)`, com `SELECT TOP (?) ... WHERE publicado_em IS NULL AND proxima_tentativa_em <= ? ORDER BY proxima_tentativa_em, ocorrido_em, id`. O índice filtrado `ix_outbox_pendente (proxima_tentativa_em, ocorrido_em, id) WHERE publicado_em IS NULL` tem exatamente a ordem da consulta. O hint de índice é necessário: sem ele, o plano pode ordenar depois de ler, o `TOP` só corta depois de bloquear todos os pendentes e um segundo publicador não encontra nada, ou seja, o `READPAST` deixa de dividir o lote.
6. **Azure:** servidor com TLS 1.2 mínimo e endpoint público, regra de firewall "Permitir serviços do Azure" (0.0.0.0) e, opcionalmente, o IP do administrador. Banco `GP_S_Gen5_2` com `useFreeLimit: true`, `freeLimitExhaustionBehavior: 'AutoPause'` e `autoPauseDelay: 60`. A URL JDBC usa `encrypt=true;trustServerCertificate=false;loginTimeout=60`. Usuário e senha de cada serviço ficam em secrets do Container App (ou nas configurações da Function).

## Consequências

- O isolamento passou a ser por permissão, não por banco. A recusa foi verificada no SQL Server local: o usuário `operacoes` recebe `Msg 229` ao ler `identidade.usuario`, ao ler por uma view no próprio schema e ao ler `indicadores.flyway_schema_history`, e `Msg 2760` ao criar tabela em `identidade`.
- A transação de abastecimento, hodômetro e outbox continua local a um schema (ADR 0013); dois publicadores concorrentes publicam cada evento uma vez.
- Os bancos compartilham CPU e armazenamento do mesmo banco serverless. Um serviço muito ativo pode afetar os outros; para o volume acadêmico, o limite gratuito basta.
- Quando o limite gratuito mensal se esgota, o banco **pausa** em vez de cobrar, e o sistema fica indisponível até o mês seguinte.
- Depois do auto-pause, a primeira conexão leva cerca de 1 min; o `loginTimeout=60` cobre esse tempo (ver ADR 0044).
- O endpoint do banco é público com TLS; o risco foi aceito pelo responsável na spec da v1.0.0. Conexões sem TLS são recusadas.
- As migrações V2–V5 de cada serviço e as ADRs que descrevem PostgreSQL ficam como histórico.

## Alternativas rejeitadas

- **Um Azure SQL Database por serviço:** só um banco por assinatura entra na oferta gratuita.
- **Logins no `master` com o prefixo `nexfleet_`:** exigiriam acesso ao `master` e um nome diferente do schema; o usuário contido com o nome do schema é criado pelo mesmo script no SQL Server local e no Azure.
- **Manter as migrações V1–V5 traduzidas:** sem dados para migrar, um V1 limpo por serviço é mais simples de revisar.
- **`create-schemas=true` no Flyway:** exigiria dar `CREATE SCHEMA` ao usuário do serviço.
