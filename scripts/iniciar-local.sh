#!/usr/bin/env bash
# Prepara a execução local: cria .env a partir de .env.example com senhas aleatórias
# (sem sobrescrever um .env existente) e gera a chave RSA da Identidade.
set -euo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$raiz"

# Senha aceita pela política do SQL Server (maiúscula, minúscula, dígito e símbolo) e
# segura para URL e para literais T-SQL (sem aspas, @, : ou /).
senha() {
  local aleatorio
  aleatorio="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24 || true)"
  printf 'Nf9_%s' "$aleatorio"
}

if [[ -f .env ]]; then
  echo ".env já existe; nada foi alterado (apague-o para gerar outro)."
else
  cp .env.example .env
  chmod 600 .env
  for marcador in $(grep -v '^#' .env.example | grep -o 'SUBSTITUA_[A-Z][A-Z_]*' | sort -u); do
    valor="$(senha)"
    sed -i.bak "s/${marcador}/${valor}/g" .env
  done
  rm -f .env.bak
  echo ".env criado com senhas aleatórias. Login local: $(grep '^LOCAL_USER_EMAIL=' .env | cut -d= -f2) (senha em LOCAL_USER_PASSWORD)."
fi

"$raiz/scripts/gerar-chave-jwt.sh"

# Avisa sobre portas já ocupadas (ajuste-as no .env).
if command -v ss >/dev/null 2>&1; then
  for var in GATEWAY_PORT SQLSERVER_PORT MONGO_PORT RABBITMQ_MGMT_PORT FUNCTION_PORT; do
    porta="$(grep "^${var}=" .env | cut -d= -f2)"
    if [[ -n "$porta" ]] && ss -ltn "sport = :$porta" | grep -q LISTEN; then
      echo "Aviso: a porta $porta ($var) já está em uso; troque-a no .env." >&2
    fi
  done
fi
