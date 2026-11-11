#!/usr/bin/env bash
# Clona os 8 repositórios irmãos ao lado do guarda-chuva (ignora os que já existem).
# Uso: scripts/clonar-tudo.sh [dono-no-github]   (padrão: mateusblm)
set -euo pipefail

dono="${1:-${NEXFLEET_GITHUB_OWNER:-mateusblm}}"
raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
destino="$(dirname "$raiz")"

for repo in frontend gateway bff identidade frota operacoes indicadores function; do
  pasta="$destino/nexfleet-$repo"
  if [[ -d "$pasta" ]]; then
    echo "nexfleet-$repo já existe em $pasta; ignorado."
  else
    git clone "https://github.com/$dono/nexfleet-$repo.git" "$pasta"
  fi
done
