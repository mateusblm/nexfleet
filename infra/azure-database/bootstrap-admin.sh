#!/bin/sh
# Provisiona o primeiro Administrador da homologacao Azure, equivalente ao LocalSeedConfig, que
# nunca deve ser habilitado na nuvem. Recebe somente o hash BCrypt (custo 12), gerado fora da
# Azure; a senha em texto claro nunca entra no job. Idempotente: uma segunda execucao nao altera
# senha, perfil ou estado de uma conta existente.
set -eu

: "${DB_HOST:?DB_HOST obrigatorio}"
: "${IDENTIDADE_DB_USER:?IDENTIDADE_DB_USER obrigatorio}"
: "${IDENTIDADE_DB_PASSWORD:?IDENTIDADE_DB_PASSWORD obrigatorio}"
: "${ADMIN_EMAIL:?ADMIN_EMAIL obrigatorio}"
: "${ADMIN_PASSWORD_HASH:?ADMIN_PASSWORD_HASH obrigatorio}"

export PGHOST="$DB_HOST"
export PGPORT="${DB_PORT:-5432}"
export PGSSLMODE="${DB_SSLMODE:-require}"
export PGDATABASE=identidade
export PGUSER="$IDENTIDADE_DB_USER"
export PGPASSWORD="$IDENTIDADE_DB_PASSWORD"

psql --no-password -v ON_ERROR_STOP=1 -v email="$ADMIN_EMAIL" -v hash="$ADMIN_PASSWORD_HASH" <<'SQL'
INSERT INTO identidade.usuario (id, email, senha_hash, perfil)
VALUES (gen_random_uuid(), lower(trim(:'email')), :'hash', 'ADMINISTRADOR')
ON CONFLICT (email) DO NOTHING;
SELECT 'NexFleet: administradores ativos = ' || count(*)
  FROM identidade.usuario WHERE perfil = 'ADMINISTRADOR' AND ativo;
SQL
