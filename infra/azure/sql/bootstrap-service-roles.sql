\set ON_ERROR_STOP on
\set ECHO none
\set QUIET 1

-- Execute conectado ao banco postgres com o administrador temporario.
-- Todos os logins e senhas chegam pelo ambiente do processo; nenhum segredo fica neste arquivo
-- ou na linha de comando do psql.
\getenv identidade_login IDENTIDADE_DB_USER
\getenv identidade_password IDENTIDADE_DB_PASSWORD
\getenv frota_login FROTA_DB_USER
\getenv frota_password FROTA_DB_PASSWORD
\getenv operacoes_login OPERACOES_DB_USER
\getenv operacoes_password OPERACOES_DB_PASSWORD
\getenv indicadores_login INDICADORES_DB_USER
\getenv indicadores_password INDICADORES_DB_PASSWORD
\getenv notificacoes_login NOTIFICACOES_DB_USER
\getenv notificacoes_password NOTIFICACOES_DB_PASSWORD

BEGIN;

SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'identidade_login') AS role_exists
\gset identidade_
\if :identidade_role_exists
  ALTER ROLE :"identidade_login" WITH LOGIN PASSWORD :'identidade_password'
    NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
\else
  CREATE ROLE :"identidade_login" WITH LOGIN PASSWORD :'identidade_password'
    NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
\endif

SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'frota_login') AS role_exists
\gset frota_
\if :frota_role_exists
  ALTER ROLE :"frota_login" WITH LOGIN PASSWORD :'frota_password'
    NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
\else
  CREATE ROLE :"frota_login" WITH LOGIN PASSWORD :'frota_password'
    NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
\endif

SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'operacoes_login') AS role_exists
\gset operacoes_
\if :operacoes_role_exists
  ALTER ROLE :"operacoes_login" WITH LOGIN PASSWORD :'operacoes_password'
    NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
\else
  CREATE ROLE :"operacoes_login" WITH LOGIN PASSWORD :'operacoes_password'
    NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
\endif

SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'indicadores_login') AS role_exists
\gset indicadores_
\if :indicadores_role_exists
  ALTER ROLE :"indicadores_login" WITH LOGIN PASSWORD :'indicadores_password'
    NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
\else
  CREATE ROLE :"indicadores_login" WITH LOGIN PASSWORD :'indicadores_password'
    NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
\endif

SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'notificacoes_login') AS role_exists
\gset notificacoes_
\if :notificacoes_role_exists
  ALTER ROLE :"notificacoes_login" WITH LOGIN PASSWORD :'notificacoes_password'
    NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
\else
  CREATE ROLE :"notificacoes_login" WITH LOGIN PASSWORD :'notificacoes_password'
    NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
\endif

-- Retira o acesso padrao entre bancos. O administrador/owner preserva seus privilegios.
REVOKE CONNECT ON DATABASE identidade FROM PUBLIC;
REVOKE CONNECT ON DATABASE frota FROM PUBLIC;
REVOKE CONNECT ON DATABASE operacoes FROM PUBLIC;
REVOKE CONNECT ON DATABASE indicadores FROM PUBLIC;
REVOKE CONNECT ON DATABASE notificacoes FROM PUBLIC;

GRANT CONNECT, CREATE ON DATABASE identidade TO :"identidade_login";
GRANT CONNECT, CREATE ON DATABASE frota TO :"frota_login";
GRANT CONNECT, CREATE ON DATABASE operacoes TO :"operacoes_login";
GRANT CONNECT, CREATE ON DATABASE indicadores TO :"indicadores_login";
GRANT CONNECT, CREATE ON DATABASE notificacoes TO :"notificacoes_login";

COMMIT;
