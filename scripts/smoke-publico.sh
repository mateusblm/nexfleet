#!/usr/bin/env bash
# Smoke da publicação na Azure pelas URLs públicas: frontend (SWA), AsyncAPI, login, CRUD de
# veículo, abastecimento, /aggregated-data com as três fontes, dashboard, Swagger via APIM e
# CORS, além de editar e excluir abastecimento e manutenção conferindo o dashboard. Com o az logado, confere também a infraestrutura (sem PostgreSQL/ACR, SQL com TLS 1.2).
#
#   NEXFLEET_API=https://<apim>.azure-api.net NEXFLEET_WEB=https://<swa> \
#   NEXFLEET_EMAIL=... NEXFLEET_SENHA=... scripts/smoke-publico.sh [pasta-de-evidencias]
#
# Cada verificação grava a resposta em <pasta>/NN-nome.txt; o resumo vai para <pasta>/resumo.txt.
# Sai com código 1 se alguma verificação falhar. Requer curl e jq (GNU date).
set -uo pipefail

API="${NEXFLEET_API:?Defina NEXFLEET_API}"; API="${API%/}"
WEB="${NEXFLEET_WEB:?Defina NEXFLEET_WEB}"; WEB="${WEB%/}"
EMAIL="${NEXFLEET_EMAIL:?Defina NEXFLEET_EMAIL}"
SENHA="${NEXFLEET_SENHA:?Defina NEXFLEET_SENHA}"
RG="${NEXFLEET_RESOURCE_GROUP:-rg-nexfleet-homolog}"
EVID="${1:-evidencias-smoke-$(date -u +%Y%m%dT%H%M%SZ)}"
mkdir -p "$EVID"

for cmd in curl jq; do command -v "$cmd" >/dev/null || { echo "Instale $cmd." >&2; exit 1; }; done

TOKEN=""; n=0; falhas=0; corpo_atual=""
resumo="$EVID/resumo.txt"; : >"$resumo"

# req NOME MÉTODO URL [JSON] → status em $s; corpo em $corpo_atual (arquivo de evidência).
req() {
  local nome="$1" metodo="$2" url="$3"; shift 3
  n=$((n + 1)); corpo_atual="$EVID/$(printf '%02d' "$n")-$nome.txt"
  local args=(-sS -L -o "$corpo_atual" -w '%{http_code}' -X "$metodo" "$url" --max-time 120
    -H 'Accept: application/json, text/html;q=0.9, */*;q=0.8')
  [[ -n "$TOKEN" && "$url" == "$API"* ]] && args+=(-H "Authorization: Bearer $TOKEN")
  [[ $# -ge 1 ]] && args+=(-H 'Content-Type: application/json' --data "$1")
  # Os Container Apps escalam a zero e o Azure SQL serverless pausa: a primeira chamada depois de
  # um tempo parado pode voltar 502/503/504 enquanto a réplica sobe e o banco retoma (~1 min).
  # Só GET e login repetem: um POST de escrita que estoura o tempo no Gateway pode ter sido
  # gravado mesmo assim; o login não grava nada.
  local tentativa
  for tentativa in 1 2 3 4 5 6 7 8; do
    s=$(curl "${args[@]}" 2>>"$EVID/curl.err") || s=000
    [[ ( "$metodo" == GET || "$nome" == login ) && "$s" =~ ^(000|502|503|504)$ ]] || return 0
    echo "      $nome: HTTP $s na tentativa $tentativa (partida a frio?), repetindo em 15 s" | tee -a "$resumo"
    sleep 15
  done
}

# conferir DESCRIÇÃO CONDIÇÃO-OK(0/1) DETALHE
conferir() {
  if [[ "$2" == 0 ]]; then echo "ok    $1 ($3)" | tee -a "$resumo"
  else echo "FALHA $1 ($3)" | tee -a "$resumo"; falhas=$((falhas + 1)); fi
}
esperar() { [[ "$2" == "$3" ]]; conferir "$1" $? "HTTP $2"; }

echo "API $API · WEB $WEB · evidências em $EVID" | tee -a "$resumo"

# --- Frontend e AsyncAPI --------------------------------------------------------------------
req web-raiz GET "$WEB/"; esperar "frontend responde" "$s" 200
req web-docs-eventos GET "$WEB/docs/eventos/"
grep -qi asyncapi "$corpo_atual"; conferir "/docs/eventos serve a página AsyncAPI" $? "HTTP $s"
vendor=$(grep -oE 'vendor/[^"'"'"' ]+\.js' "$corpo_atual" | head -1)
req web-docs-vendor GET "$WEB/docs/eventos/${vendor:-vendor/ausente.js}"
esperar "web component AsyncAPI servido do próprio site" "$s" 200
req web-docs-contrato GET "$WEB/docs/eventos/eventos.asyncapi.yaml"
esperar "contrato AsyncAPI publicado" "$s" 200

# --- Autenticação ---------------------------------------------------------------------------
req sem-token GET "$API/api/v1/veiculos"; esperar "API exige token" "$s" 401
req login POST "$API/api/v1/auth/login" "$(jq -nc --arg e "$EMAIL" --arg s "$SENHA" '{email:$e,senha:$s}')"
esperar "login" "$s" 200
TOKEN="$(jq -r '.accessToken // empty' "$corpo_atual" 2>/dev/null)"
jq 'del(.accessToken, .refreshToken)' "$corpo_atual" >"$corpo_atual.tmp" 2>/dev/null && mv "$corpo_atual.tmp" "$corpo_atual"
[[ -n "$TOKEN" ]] || { conferir "token recebido" 1 "sem accessToken"; exit 1; }

# --- Aquecimento: acorda Frota, Operações e Indicadores (e o SQL) antes das escritas ---------
req aquecer-frota GET "$API/api/v1/veiculos?tamanho=1"; esperar "Frota responde" "$s" 200
req aquecer-operacoes GET "$API/api/v1/manutencoes?tamanho=1"; esperar "Operações responde" "$s" 200
req aquecer-indicadores GET "$API/api/v1/dashboard"; esperar "Indicadores responde" "$s" 200
abast_antes=$(jq -r '.quantidadeAbastecimentos // 0' "$corpo_atual")
man_antes=$(jq -r '.quantidadeManutencoes // 0' "$corpo_atual")

# aguardar_dashboard CAMPO VALOR DESCRIÇÃO: o dashboard é atualizado por evento (outbox →
# Service Bus → Indicadores), então espera até 2 min pelo valor.
aguardar_dashboard() {
  local campo="$1" esperado="$2" atual="" i
  for i in $(seq 1 12); do
    req "dashboard-$campo" GET "$API/api/v1/dashboard"
    atual=$(jq -r ".$campo // empty" "$corpo_atual" 2>/dev/null)
    [[ "$atual" == "$esperado" ]] && break
    sleep 10
  done
  [[ "$atual" == "$esperado" ]]; conferir "$3" $? "$campo=$atual, esperado $esperado"
}

# --- CRUD de veículo (MongoDB Atlas) --------------------------------------------------------
letras=ABCDEFGHJKLMNPRSTUVWXYZ
placa="SMK$((RANDOM % 10))${letras:RANDOM % ${#letras}:1}$((RANDOM % 10))$((RANDOM % 10))"
veiculo=$(jq -nc --arg p "$placa" '{placa:$p,marca:"Smoke",modelo:"Teste",ano:2024,tipo:"VAN",quilometragem:1000,status:"DISPONIVEL",dataAquisicao:"2024-01-15"}')
req veiculo-criar POST "$API/api/v1/veiculos" "$veiculo"; esperar "criar veículo $placa" "$s" 201
id=$(jq -r '.id // empty' "$corpo_atual")
req veiculo-ler GET "$API/api/v1/veiculos/$id"; esperar "ler veículo" "$s" 200
req veiculo-atualizar PUT "$API/api/v1/veiculos/$id" "$(jq -c '.modelo="Teste Atualizado" | .quilometragem=1500' <<<"$veiculo")"
esperar "atualizar veículo" "$s" 200
req veiculo-inativar DELETE "$API/api/v1/veiculos/$id"; esperar "inativar veículo" "$s" 204
req veiculo-excluir DELETE "$API/api/v1/veiculos/$id/definitivo"; esperar "excluir veículo" "$s" 204

# --- Abastecimento (Azure SQL + outbox + Service Bus) ---------------------------------------
req veiculos-listar GET "$API/api/v1/veiculos?tamanho=100"; esperar "listar veículos" "$s" 200
alvo=$(jq -r '(if type == "array" then . else (.itens // .content) end) | map(select(.placa=="NXF1A01")) | .[0].id // empty' "$corpo_atual")
req abastecimentos-listar GET "$API/api/v1/abastecimentos?veiculoId=$alvo&tamanho=100"
ultimo=$(jq -c '(if type == "array" then . else (.itens // .content) end) | max_by(.quilometragem)' "$corpo_atual")
novo=$(jq -c --arg r "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{veiculoId, motoristaId, combustivel, realizadoEm:$r, litros:40.5, valorTotal:243.0, quilometragem:(.quilometragem + 420)}' <<<"$ultimo")
req abastecimento-registrar POST "$API/api/v1/abastecimentos" "$novo"; esperar "registrar abastecimento (NXF1A01)" "$s" 201
abastecimento=$(jq -r '.id // empty' "$corpo_atual")
aguardar_dashboard quantidadeAbastecimentos $((abast_antes + 1)) "dashboard conta o abastecimento novo"

# --- Edição e exclusão no Operações (CRUD completo, eventos versionados) ----------------------
req abastecimento-ler GET "$API/api/v1/abastecimentos/$abastecimento"; esperar "ler abastecimento por id" "$s" 200
req abastecimento-editar PUT "$API/api/v1/abastecimentos/$abastecimento" \
  "$(jq -c '{combustivel, litros:42.0, valorTotal:300.0, quilometragem}' <<<"$novo")"
esperar "editar abastecimento" "$s" 200
jq -e '.versao == 2 and (.valorTotal | tonumber) == 300' "$corpo_atual" >/dev/null 2>&1
conferir "edição grava o valor novo e a versão 2" $? "$(jq -c '{versao, valorTotal}' "$corpo_atual" 2>/dev/null)"
req abastecimento-km-invalido PUT "$API/api/v1/abastecimentos/$abastecimento" \
  "$(jq -c '{combustivel, litros, valorTotal, quilometragem:1}' <<<"$novo")"
esperar "km fora da faixa é recusado" "$s" 422
req abastecimento-excluir DELETE "$API/api/v1/abastecimentos/$abastecimento"; esperar "excluir abastecimento" "$s" 204
req abastecimento-excluido GET "$API/api/v1/abastecimentos/$abastecimento"; esperar "abastecimento excluído some" "$s" 404
aguardar_dashboard quantidadeAbastecimentos "$abast_antes" "dashboard tira o abastecimento excluído"

manutencao=$(jq -nc --arg v "$alvo" --arg d "$(date -u +%Y-%m-%d)" \
  '{veiculoId:$v,tipo:"REVISAO",realizadaEm:$d,quilometragem:1000,descricao:"Revisão de smoke",oficina:"Oficina Smoke",valor:150.0,proximaManutencao:null}')
req manutencao-registrar POST "$API/api/v1/manutencoes" "$manutencao"; esperar "registrar manutenção" "$s" 201
man_id=$(jq -r '.id // empty' "$corpo_atual")
req manutencao-ler GET "$API/api/v1/manutencoes/$man_id"; esperar "ler manutenção por id" "$s" 200
req manutencao-editar PUT "$API/api/v1/manutencoes/$man_id" \
  "$(jq -c 'del(.veiculoId) | .valor=180.0 | .descricao="Revisão de smoke (corrigida)"' <<<"$manutencao")"
esperar "editar manutenção" "$s" 200
req manutencao-excluir DELETE "$API/api/v1/manutencoes/$man_id"; esperar "excluir manutenção" "$s" 204
aguardar_dashboard quantidadeManutencoes "$man_antes" "dashboard volta ao total de manutenções"

# --- /aggregated-data: Frota (Mongo) + Operações (SQL) + Function ---------------------------
req aggregated-data GET "$API/aggregated-data"; esperar "GET /aggregated-data" "$s" 200
fontes=$(jq -c '.fontes' "$corpo_atual" 2>/dev/null)
jq -e '.fontes | [.frota, .operacoes, .funcao] | all(. == "ok")' "$corpo_atual" >/dev/null 2>&1
conferir "/aggregated-data com as três fontes ok" $? "$fontes"

req dashboard GET "$API/api/v1/dashboard"; esperar "dashboard (Indicadores)" "$s" 200

# --- Swagger via APIM -----------------------------------------------------------------------
req swagger-ui GET "$API/swagger-ui.html"; esperar "Swagger UI via APIM" "$s" 200
req swagger-config GET "$API/v3/api-docs/swagger-config"; esperar "swagger-config" "$s" 200
for url in $(jq -r '.urls[]?.url' "$corpo_atual"); do
  [[ "$url" == http* ]] || url="$API$url"
  nome=$(sed 's#.*/docs/\([^/]*\)/.*#\1#' <<<"$url")
  req "openapi-$nome" GET "$url"
  jq -e '.openapi' "$corpo_atual" >/dev/null 2>&1; conferir "OpenAPI de $nome" $? "HTTP $s"
done

# --- CORS do frontend publicado -------------------------------------------------------------
n=$((n + 1)); cors="$EVID/$(printf '%02d' "$n")-cors.txt"
curl -sS -o /dev/null -D "$cors" -X OPTIONS "$API/api/v1/veiculos" -H "Origin: $WEB" \
  -H 'Access-Control-Request-Method: GET' -H 'Access-Control-Request-Headers: authorization' --max-time 60
grep -qi "access-control-allow-origin: $WEB" "$cors"; conferir "CORS libera o frontend" $? "$WEB"

# --- Infraestrutura (só com az logado) ------------------------------------------------------
if command -v az >/dev/null && az account show >/dev/null 2>&1; then
  n=$((n + 1)); inv="$EVID/$(printf '%02d' "$n")-inventario.txt"
  az resource list -g "$RG" --query '[].{tipo:type,nome:name}' -o tsv >"$inv"
  ! grep -qiE 'DBforPostgreSQL|ContainerRegistry|privateDnsZones' "$inv"
  conferir "sem PostgreSQL, ACR nem DNS privado" $? "$(wc -l <"$inv") recursos"
  sql=$(awk -F'\t' '$1=="Microsoft.Sql/servers"{print $2}' "$inv" | head -1)
  tls=$(az sql server show -g "$RG" -n "$sql" --query minimalTlsVersion -o tsv 2>/dev/null)
  [[ "$tls" == 1.2 || "$tls" == 1.3 ]]; conferir "Azure SQL recusa conexão sem TLS (mínimo $tls)" $? "$sql"
else
  echo "pulei  infraestrutura (az não logado)" | tee -a "$resumo"
fi

echo "---" | tee -a "$resumo"
echo "$n verificações gravadas, $falhas falha(s)." | tee -a "$resumo"
[[ "$falhas" == 0 ]]
