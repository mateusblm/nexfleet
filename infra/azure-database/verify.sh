#!/bin/sh
# Prova pos-migracao executada dentro da VNet: cada papel conecta somente no proprio banco
# e cada banco possui exatamente as versoes Flyway esperadas (17 no total).
set -eu

: "${DB_HOST:?DB_HOST obrigatorio}"
export PGHOST="$DB_HOST"
export PGPORT="${DB_PORT:-5432}"
export PGSSLMODE="${DB_SSLMODE:-require}"

failures=0
total=0

check_service() {
  database="$1"
  user="$2"
  password="$3"
  expected="$4"
  other="$5"

  count=$(PGUSER="$user" PGPASSWORD="$password" psql --no-password -d "$database" -tA \
    -c "SELECT count(*) FROM ${database}.flyway_schema_history WHERE success AND version IS NOT NULL;")
  total=$((total + count))
  if [ "$count" -ne "$expected" ]; then
    echo "FALHA: ${database} possui ${count} migracoes; esperado ${expected}."
    failures=$((failures + 1))
  else
    echo "OK: ${database} com ${count} migracoes aplicadas pelo proprio papel."
  fi

  if PGUSER="$user" PGPASSWORD="$password" psql --no-password -d "$other" -tA -c 'SELECT 1;' >/dev/null 2>&1; then
    echo "FALHA: papel de ${database} conectou no banco ${other}."
    failures=$((failures + 1))
  else
    echo "OK: papel de ${database} recusado no banco ${other}."
  fi
}

check_service identidade "$IDENTIDADE_DB_USER" "$IDENTIDADE_DB_PASSWORD" 3 frota
check_service frota "$FROTA_DB_USER" "$FROTA_DB_PASSWORD" 4 operacoes
check_service operacoes "$OPERACOES_DB_USER" "$OPERACOES_DB_PASSWORD" 5 indicadores
check_service indicadores "$INDICADORES_DB_USER" "$INDICADORES_DB_PASSWORD" 3 notificacoes
check_service notificacoes "$NOTIFICACOES_DB_USER" "$NOTIFICACOES_DB_PASSWORD" 2 identidade

if [ "$failures" -ne 0 ] || [ "$total" -ne 17 ]; then
  echo "NexFleet: verificacao reprovada (${failures} falha(s); ${total}/17 migracoes)."
  exit 1
fi
echo 'NexFleet: verificacao aprovada: 17 migracoes e isolamento entre os cinco bancos.'
