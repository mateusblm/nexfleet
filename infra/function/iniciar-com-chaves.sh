#!/usr/bin/env bash
# Sobe o host de Functions local com chaves conhecidas.
#
# O gatilho HTTP CalcularEficiencia usa authLevel=FUNCTION: o host responde 401 sem a chave.
# Com AzureWebJobsSecretStorageType=files, o host lê as chaves de
# /azure-functions-host/Secrets/host.json (lido sob demanda; formato do runtime v4).
# A chave em "functionKeys" vale para qualquer função (chave de host), então o BFF usa a
# mesma EFICIENCIA_FUNCTION_KEY no cabeçalho x-functions-key.
# Na Azure as chaves ficam no Storage da Function App e este script não é usado.
set -euo pipefail

: "${EFICIENCIA_FUNCTION_KEY:?Defina EFICIENCIA_FUNCTION_KEY}"
: "${FUNCTION_MASTER_KEY:?Defina FUNCTION_MASTER_KEY}"

pasta=/azure-functions-host/Secrets
mkdir -p "$pasta"
umask 077
cat > "$pasta/host.json" <<EOF
{
  "masterKey": { "name": "master", "value": "${FUNCTION_MASTER_KEY}", "encrypted": false },
  "functionKeys": [ { "name": "default", "value": "${EFICIENCIA_FUNCTION_KEY}", "encrypted": false } ],
  "systemKeys": []
}
EOF

exec /opt/startup/start_nonappservice.sh
