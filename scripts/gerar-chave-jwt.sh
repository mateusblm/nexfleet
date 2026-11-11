#!/usr/bin/env bash
# Gera a chave RSA privada (PKCS#8, 3072 bits) que a Identidade usa para assinar o JWT.
# Equivalente bash de New-LocalJwtKey.ps1. Nunca substitui uma chave existente: isso
# invalidaria as sessões. Uso: scripts/gerar-chave-jwt.sh [destino]
set -euo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
destino="${1:-$raiz/.secrets/identidade-jwt.pem}"

if [[ -e "$destino" ]]; then
  echo "A chave RSA já existe em $destino e não será substituída." >&2
  exit 0
fi

mkdir -p "$(dirname "$destino")"
umask 077
if command -v openssl >/dev/null 2>&1; then
  openssl genpkey -quiet -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out "$destino"
else
  pasta="$(cd "$(dirname "$destino")" && pwd)"
  docker run --rm --user "$(id -u):$(id -g)" \
    --mount "type=bind,source=$pasta,target=/out" eclipse-temurin:21-jre-jammy \
    sh -c "umask 077; openssl genpkey -quiet -algorithm RSA -pkeyopt rsa_keygen_bits:3072 -out /out/$(basename "$destino")"
fi
echo "Chave RSA local criada em $destino. Não compartilhe esse arquivo."
