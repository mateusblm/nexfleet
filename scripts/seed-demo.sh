#!/usr/bin/env bash
# Seed de demonstração pela API pública do Gateway: veículos, motoristas, vínculos,
# abastecimentos (quilometragem crescente) e manutenções (datas variadas).
#
#   scripts/seed-demo.sh                                   # local, lê o .env
#   NEXFLEET_API=https://<gateway> NEXFLEET_EMAIL=... NEXFLEET_SENHA=... scripts/seed-demo.sh
#
# Idempotente o bastante para rodar de novo: 409 (placa/CPF/CNH/vínculo já existentes) é
# ignorado, e abastecimentos/manutenções só são criados para veículo que ainda não tem nenhum.
# Requer curl e jq.
#
# Abastecimentos precisam de vínculo vigente no instante informado (regra da Frota), e o
# vínculo começa agora: por isso eles recebem instantes de agora, em sequência, enquanto as
# manutenções usam datas passadas variadas.
set -euo pipefail

raiz="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ler_env() { [[ -f "$raiz/.env" ]] && grep -E "^$1=" "$raiz/.env" | tail -1 | cut -d= -f2- || true; }

API="${NEXFLEET_API:-http://127.0.0.1:$(ler_env GATEWAY_PORT | grep . || echo 8080)}"
API="${API%/}"
EMAIL="${NEXFLEET_EMAIL:-$(ler_env LOCAL_USER_EMAIL)}"
SENHA="${NEXFLEET_SENHA:-$(ler_env LOCAL_USER_PASSWORD)}"
: "${EMAIL:?Defina NEXFLEET_EMAIL (ou LOCAL_USER_EMAIL no .env)}"
: "${SENHA:?Defina NEXFLEET_SENHA (ou LOCAL_USER_PASSWORD no .env)}"

for cmd in curl jq; do
  command -v "$cmd" >/dev/null || { echo "Instale $cmd." >&2; exit 1; }
done

TOKEN=""
resposta="$(mktemp)"
trap 'rm -f "$resposta"' EXIT

# chamar MÉTODO CAMINHO [JSON] → imprime o status; corpo em $resposta.
chamar() {
  local args=(-sS -o "$resposta" -w '%{http_code}' -X "$1" "$API$2"
    -H 'Accept: application/json' --max-time 30)
  [[ -n "$TOKEN" ]] && args+=(-H "Authorization: Bearer $TOKEN")
  [[ $# -ge 3 ]] && args+=(-H 'Content-Type: application/json' --data "$3")
  curl "${args[@]}"
}

falhar() { echo "Falhou: $1 → HTTP $2: $(head -c 400 "$resposta")" >&2; exit 1; }

instante() { date -u -d "${1:-now}" +%Y-%m-%dT%H:%M:%SZ; }
dia() { date -u -d "$1" +%Y-%m-%d; }

echo "API: $API"
status="$(chamar POST /api/v1/auth/login "$(jq -nc --arg e "$EMAIL" --arg s "$SENHA" '{email:$e,senha:$s}')")"
[[ "$status" == 200 ]] || falhar "login de $EMAIL" "$status"
TOKEN="$(jq -r .accessToken "$resposta")"
echo "Login ok ($EMAIL)."

# --- Veículos ---------------------------------------------------------------------------
# placa|marca|modelo|ano|tipo|km inicial|aquisição
VEICULOS=(
  "NXF1A01|Volkswagen|Delivery 11.180|2021|CAMINHAO|48200|2021-03-10"
  "NXF2B02|Fiat|Strada Freedom|2022|UTILITARIO|31500|2022-01-18"
  "NXF3C03|Renault|Master Furgão|2020|VAN|76400|2020-07-02"
  "NXF4D04|Toyota|Hilux SR|2023|CAMINHONETE|15800|2023-05-22"
  "NXF5E05|Mercedes-Benz|Sprinter 416|2019|VAN|98100|2019-11-11"
)
declare -A VEICULO_ID VEICULO_KM

listar_veiculos() {
  local status
  status="$(chamar GET '/api/v1/veiculos?tamanho=100')"
  [[ "$status" == 200 ]] || falhar "listar veículos" "$status"
}

for linha in "${VEICULOS[@]}"; do
  IFS='|' read -r placa marca modelo ano tipo km aquisicao <<<"$linha"
  corpo="$(jq -nc --arg p "$placa" --arg ma "$marca" --arg mo "$modelo" --argjson a "$ano" \
    --arg t "$tipo" --argjson k "$km" --arg d "$aquisicao" \
    '{placa:$p,marca:$ma,modelo:$mo,ano:$a,tipo:$t,quilometragem:$k,status:"DISPONIVEL",dataAquisicao:$d}')"
  status="$(chamar POST /api/v1/veiculos "$corpo")"
  case "$status" in
    201) VEICULO_ID[$placa]="$(jq -r .id "$resposta")"; echo "Veículo $placa criado." ;;
    409)
      listar_veiculos
      VEICULO_ID[$placa]="$(jq -r --arg p "$placa" '.[] | select(.placa==$p) | .id' "$resposta")"
      [[ -n "${VEICULO_ID[$placa]}" ]] || falhar "localizar veículo $placa" 409
      echo "Veículo $placa já existia." ;;
    *) falhar "criar veículo $placa" "$status" ;;
  esac
  VEICULO_KM[$placa]="$km"
done

# --- Motoristas -------------------------------------------------------------------------
# nome|cpf|cnh|categoria|validade|telefone
MOTORISTAS=(
  "Ana Paula Ribeiro|52998224725|10293847561|D|2029-06-30|(41) 99811-2031"
  "Bruno Henrique Costa|11144477735|20394857612|B|2028-02-15|(41) 99722-4410"
  "Carla Mendes Souza|39053344705|30495867123|C|2030-09-01|(41) 99633-7788"
  "Diego Almeida Santos|71428793860|40596871234|B|2027-12-20|(41) 99544-1290"
  "Eduarda Lima Ferreira|86288366757|50617283945|D|2031-03-12|(41) 99455-6603"
)
MOTORISTA_IDS=()

for linha in "${MOTORISTAS[@]}"; do
  IFS='|' read -r nome cpf cnh categoria validade telefone <<<"$linha"
  corpo="$(jq -nc --arg n "$nome" --arg c "$cpf" --arg h "$cnh" --arg k "$categoria" \
    --arg v "$validade" --arg t "$telefone" \
    '{nome:$n,cpf:$c,cnh:$h,categoria:$k,validadeCnh:$v,telefone:$t,status:"ATIVO"}')"
  status="$(chamar POST /api/v1/motoristas "$corpo")"
  case "$status" in
    201) MOTORISTA_IDS+=("$(jq -r .id "$resposta")"); echo "Motorista $nome criado." ;;
    409)
      status="$(chamar GET '/api/v1/motoristas?tamanho=100')"
      [[ "$status" == 200 ]] || falhar "listar motoristas" "$status"
      id="$(jq -r --arg c "$cpf" '.[] | select((.cpf|gsub("\\D";""))==$c) | .id' "$resposta")"
      [[ -n "$id" ]] || falhar "localizar motorista $nome" 409
      MOTORISTA_IDS+=("$id"); echo "Motorista $nome já existia." ;;
    *) falhar "criar motorista $nome" "$status" ;;
  esac
done

# --- Vínculos (um por veículo) ----------------------------------------------------------
i=0
for linha in "${VEICULOS[@]}"; do
  placa="${linha%%|*}"
  corpo="$(jq -nc --arg v "${VEICULO_ID[$placa]}" --arg m "${MOTORISTA_IDS[$i]}" '{veiculoId:$v,motoristaId:$m}')"
  status="$(chamar POST /api/v1/vinculos "$corpo")"
  case "$status" in
    201) echo "Vínculo $placa ↔ motorista $((i + 1)) criado." ;;
    409|422) echo "Vínculo de $placa já existia (HTTP $status)." ;;
    *) falhar "vincular $placa" "$status" ;;
  esac
  i=$((i + 1))
done

# --- Abastecimentos (3 por veículo, quilometragem crescente) ----------------------------
COMBUSTIVEL=(DIESEL GASOLINA DIESEL DIESEL DIESEL)
PRECO=(6.19 5.89 6.09 6.29 6.15)
sleep 2   # o vínculo começa no instante da criação; o abastecimento precisa ser posterior
i=0
for linha in "${VEICULOS[@]}"; do
  placa="${linha%%|*}"
  veiculo="${VEICULO_ID[$placa]}"
  status="$(chamar GET "/api/v1/abastecimentos?veiculoId=$veiculo&tamanho=1")"
  [[ "$status" == 200 ]] || falhar "consultar abastecimentos de $placa" "$status"
  if [[ "$(jq 'length' "$resposta")" -gt 0 ]]; then
    echo "Abastecimentos de $placa já existiam."
  else
    km="${VEICULO_KM[$placa]}"
    for n in 1 2 3; do
      km=$((km + 380 + (i * 47) + (n * 61)))
      litros="$(awk -v n="$n" -v i="$i" 'BEGIN{printf "%.2f", 38 + n*4.5 + i*3.25}')"
      valor="$(awk -v l="$litros" -v p="${PRECO[$i]}" 'BEGIN{printf "%.2f", l*p}')"
      corpo="$(jq -nc --arg v "$veiculo" --arg m "${MOTORISTA_IDS[$i]}" --arg r "$(instante)" \
        --arg c "${COMBUSTIVEL[$i]}" --argjson l "$litros" --argjson vt "$valor" --argjson k "$km" \
        '{veiculoId:$v,motoristaId:$m,realizadoEm:$r,combustivel:$c,litros:$l,valorTotal:$vt,quilometragem:$k}')"
      status="$(chamar POST /api/v1/abastecimentos "$corpo")"
      [[ "$status" == 201 ]] || falhar "abastecer $placa (km $km)" "$status"
    done
    echo "3 abastecimentos de $placa registrados (até $km km)."
  fi
  i=$((i + 1))
done

# --- Manutenções (datas passadas variadas, próxima revisão futura) ----------------------
# índice do veículo|tipo|dias atrás|valor|descrição|oficina|próxima em (dias)
MANUTENCOES=(
  "0|PREVENTIVA|120|1480.00|Revisão dos 50 mil km|Oficina Central Curitiba|60"
  "0|TROCA_PNEUS|45|2360.00|Troca dos pneus traseiros|Pneus Paraná|"
  "1|TROCA_OLEO|30|289.90|Troca de óleo e filtro|Auto Center Batel|90"
  "2|CORRETIVA|75|3120.50|Substituição da embreagem|Oficina Central Curitiba|"
  "3|REVISAO|15|890.00|Revisão de garantia|Concessionária Toyota|180"
  "4|PREVENTIVA|200|1675.40|Freios e suspensão|Sprinter Service|20"
)
declare -A TEM_MANUTENCAO
for linha in "${MANUTENCOES[@]}"; do
  IFS='|' read -r idx tipo atras valor descricao oficina proxima <<<"$linha"
  linha_veiculo="${VEICULOS[$idx]}"
  placa="${linha_veiculo%%|*}"
  veiculo="${VEICULO_ID[$placa]}"
  if [[ -z "${TEM_MANUTENCAO[$placa]:-}" ]]; then
    status="$(chamar GET "/api/v1/manutencoes?veiculoId=$veiculo&tamanho=1")"
    [[ "$status" == 200 ]] || falhar "consultar manutenções de $placa" "$status"
    if [[ "$(jq 'length' "$resposta")" -gt 0 ]]; then TEM_MANUTENCAO[$placa]=sim; else TEM_MANUTENCAO[$placa]=nao; fi
  fi
  if [[ "${TEM_MANUTENCAO[$placa]}" == sim ]]; then
    echo "Manutenção ($tipo) de $placa ignorada: o veículo já tinha manutenções."
    continue
  fi
  km=$(( ${VEICULO_KM[$placa]} - atras * 3 ))
  (( km < 0 )) && km=0
  proxima_json=null
  [[ -n "$proxima" ]] && proxima_json="\"$(dia "+$proxima days")\""
  corpo="$(jq -nc --arg v "$veiculo" --arg t "$tipo" --arg r "$(dia "-$atras days")" --argjson k "$km" \
    --arg d "$descricao" --arg o "$oficina" --argjson vl "$valor" --argjson p "$proxima_json" \
    '{veiculoId:$v,tipo:$t,realizadaEm:$r,quilometragem:$k,descricao:$d,oficina:$o,valor:$vl,proximaManutencao:$p}')"
  status="$(chamar POST /api/v1/manutencoes "$corpo")"
  [[ "$status" == 201 ]] || falhar "registrar manutenção $tipo de $placa" "$status"
  echo "Manutenção $tipo de $placa registrada ($(dia "-$atras days"))."
done

echo "Seed concluído: ${#VEICULOS[@]} veículos, ${#MOTORISTAS[@]} motoristas, vínculos, 15 abastecimentos e ${#MANUTENCOES[@]} manutenções."
