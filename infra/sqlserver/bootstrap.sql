-- Bootstrap do banco NexFleet (SQL Server 2022 local e Azure SQL Database).
-- Executado pelo administrador com sqlcmd; é idempotente (pode rodar a cada subida).
--
--   sqlcmd -S <servidor> -U <admin> -P <senha> -C -b -d master -i bootstrap.sql   (local)
--   sqlcmd -S <srv>.database.windows.net -U <admin> -d nexfleet -b -i bootstrap.sql (Azure)
--
-- Variáveis sqlcmd (lidas também do ambiente): NEXFLEET_DB, IDENTIDADE_DB_PASSWORD,
-- OPERACOES_DB_PASSWORD, INDICADORES_DB_PASSWORD, NOTIFICACOES_DB_PASSWORD.
-- As senhas são interpoladas em texto: não use aspas simples nelas.
--
-- Decisões:
-- * Usuários contidos (CREATE USER ... WITH PASSWORD): o Azure SQL Database não tem
--   CREATE LOGIN no banco de usuário. No SQL Server local o script habilita a autenticação
--   de banco contido e deixa o banco com CONTAINMENT = PARTIAL antes de criar os usuários.
-- * Cada schema pertence ao usuário do próprio serviço (ALTER AUTHORIZATION). Assim o
--   Flyway do serviço cria e altera tabelas ali, e os objetos criados pertencem ao serviço:
--   não há encadeamento de propriedade (ownership chaining) com objetos de outro schema,
--   que permitiria ler outro schema por uma view se todos pertencessem a dbo.
-- * Fora do próprio schema o usuário só recebe CREATE TABLE/VIEW no banco (exigido pelo
--   SQL Server para criar objetos em qualquer schema) e nenhum SELECT/INSERT em outro.

:on error exit

-- 1. Banco e autenticação contida: só no SQL Server (EngineEdition 5 = Azure SQL Database,
--    onde o banco já existe e já aceita usuários contidos).
IF CAST(SERVERPROPERTY('EngineEdition') AS INT) <> 5
BEGIN
  IF EXISTS (SELECT 1 FROM sys.configurations
             WHERE name = 'contained database authentication' AND CAST(value_in_use AS INT) = 0)
  BEGIN
    -- Dinâmico: o Azure SQL Database não compila RECONFIGURE, mesmo em ramo não executado.
    EXEC (N'EXEC sys.sp_configure N''contained database authentication'', 1; RECONFIGURE;');
  END;
  IF DB_ID(N'$(NEXFLEET_DB)') IS NULL
    EXEC (N'CREATE DATABASE [$(NEXFLEET_DB)]');
  IF EXISTS (SELECT 1 FROM sys.databases WHERE name = N'$(NEXFLEET_DB)' AND containment = 0)
    EXEC (N'ALTER DATABASE [$(NEXFLEET_DB)] SET CONTAINMENT = PARTIAL');
END;
GO

-- No Azure SQL Database, USE só aceita o banco da conexão atual (que é o próprio nexfleet).
USE [$(NEXFLEET_DB)];
GO

-- 2. Um usuário contido por serviço. Se já existir, a senha é sincronizada com o .env.
CREATE OR ALTER PROCEDURE dbo.nexfleet_garantir_servico
  @servico SYSNAME,
  @senha NVARCHAR(128)
AS
BEGIN
  SET NOCOUNT ON;
  DECLARE @sql NVARCHAR(MAX);
  DECLARE @senhaLiteral NVARCHAR(300) = N'N' + QUOTENAME(@senha, N'''');

  IF DATABASE_PRINCIPAL_ID(@servico) IS NULL
    SET @sql = N'CREATE USER ' + QUOTENAME(@servico) + N' WITH PASSWORD = ' + @senhaLiteral
      + N', DEFAULT_SCHEMA = ' + QUOTENAME(@servico) + N';';
  ELSE
    SET @sql = N'ALTER USER ' + QUOTENAME(@servico) + N' WITH PASSWORD = ' + @senhaLiteral
      + N', DEFAULT_SCHEMA = ' + QUOTENAME(@servico) + N';';
  EXEC (@sql);

  IF SCHEMA_ID(@servico) IS NULL
  BEGIN
    SET @sql = N'CREATE SCHEMA ' + QUOTENAME(@servico) + N' AUTHORIZATION ' + QUOTENAME(@servico) + N';';
    EXEC (@sql);
  END
  ELSE IF SCHEMA_ID(@servico) NOT IN (SELECT schema_id FROM sys.schemas
                                      WHERE principal_id = DATABASE_PRINCIPAL_ID(@servico))
  BEGIN
    SET @sql = N'ALTER AUTHORIZATION ON SCHEMA::' + QUOTENAME(@servico) + N' TO ' + QUOTENAME(@servico) + N';';
    EXEC (@sql);
  END;

  SET @sql = N'GRANT CREATE TABLE, CREATE VIEW TO ' + QUOTENAME(@servico) + N';';
  EXEC (@sql);
END;
GO

EXEC dbo.nexfleet_garantir_servico N'identidade', N'$(IDENTIDADE_DB_PASSWORD)';
EXEC dbo.nexfleet_garantir_servico N'operacoes', N'$(OPERACOES_DB_PASSWORD)';
EXEC dbo.nexfleet_garantir_servico N'indicadores', N'$(INDICADORES_DB_PASSWORD)';
EXEC dbo.nexfleet_garantir_servico N'notificacoes', N'$(NOTIFICACOES_DB_PASSWORD)';
GO

DROP PROCEDURE dbo.nexfleet_garantir_servico;
GO

PRINT N'Bootstrap NexFleet concluído: schemas identidade, operacoes, indicadores e notificacoes.';
GO
