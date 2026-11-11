#!/bin/sh
set -eu

: "${DB_HOST:?DB_HOST obrigatorio}"
: "${POSTGRES_ADMIN_USER:?POSTGRES_ADMIN_USER obrigatorio}"
: "${POSTGRES_ADMIN_PASSWORD:?POSTGRES_ADMIN_PASSWORD obrigatorio}"
: "${IDENTIDADE_DB_USER:?IDENTIDADE_DB_USER obrigatorio}"
: "${IDENTIDADE_DB_PASSWORD:?IDENTIDADE_DB_PASSWORD obrigatorio}"
: "${FROTA_DB_USER:?FROTA_DB_USER obrigatorio}"
: "${FROTA_DB_PASSWORD:?FROTA_DB_PASSWORD obrigatorio}"
: "${OPERACOES_DB_USER:?OPERACOES_DB_USER obrigatorio}"
: "${OPERACOES_DB_PASSWORD:?OPERACOES_DB_PASSWORD obrigatorio}"
: "${INDICADORES_DB_USER:?INDICADORES_DB_USER obrigatorio}"
: "${INDICADORES_DB_PASSWORD:?INDICADORES_DB_PASSWORD obrigatorio}"
: "${NOTIFICACOES_DB_USER:?NOTIFICACOES_DB_USER obrigatorio}"
: "${NOTIFICACOES_DB_PASSWORD:?NOTIFICACOES_DB_PASSWORD obrigatorio}"

export PGHOST="$DB_HOST"
export PGPORT="${DB_PORT:-5432}"
export PGDATABASE=postgres
export PGUSER="$POSTGRES_ADMIN_USER"
export PGPASSWORD="$POSTGRES_ADMIN_PASSWORD"
export PGSSLMODE="${DB_SSLMODE:-require}"

echo 'NexFleet: provisionando os cinco papeis PostgreSQL isolados.'
psql --no-password --file=/nexfleet/bootstrap-service-roles.sql
unset PGPASSWORD POSTGRES_ADMIN_PASSWORD

migrate_database() {
  database="$1"
  schema="$2"
  user="$3"
  password="$4"

  echo "NexFleet: aplicando migracoes do banco ${database}."
  export FLYWAY_URL="jdbc:postgresql://${DB_HOST}:${DB_PORT:-5432}/${database}?sslmode=${DB_SSLMODE:-require}"
  export FLYWAY_USER="$user"
  export FLYWAY_PASSWORD="$password"
  export FLYWAY_SCHEMAS="$schema"
  export FLYWAY_DEFAULT_SCHEMA="$schema"
  export FLYWAY_LOCATIONS="filesystem:/nexfleet/migrations/${database}"
  export FLYWAY_BASELINE_ON_MIGRATE=true
  /flyway/flyway migrate
  unset FLYWAY_URL FLYWAY_USER FLYWAY_PASSWORD FLYWAY_SCHEMAS FLYWAY_DEFAULT_SCHEMA FLYWAY_LOCATIONS FLYWAY_BASELINE_ON_MIGRATE
}

migrate_database identidade identidade "$IDENTIDADE_DB_USER" "$IDENTIDADE_DB_PASSWORD"
migrate_database frota frota "$FROTA_DB_USER" "$FROTA_DB_PASSWORD"
migrate_database operacoes operacoes "$OPERACOES_DB_USER" "$OPERACOES_DB_PASSWORD"
migrate_database indicadores indicadores "$INDICADORES_DB_USER" "$INDICADORES_DB_PASSWORD"
migrate_database notificacoes notificacoes "$NOTIFICACOES_DB_USER" "$NOTIFICACOES_DB_PASSWORD"

unset IDENTIDADE_DB_PASSWORD FROTA_DB_PASSWORD OPERACOES_DB_PASSWORD INDICADORES_DB_PASSWORD NOTIFICACOES_DB_PASSWORD
echo 'NexFleet: bootstrap e migracoes concluidos com sucesso.'
