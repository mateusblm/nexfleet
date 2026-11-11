# Aula 20 — correlação ponta a ponta

## O problema

Uma única ação da tela pode produzir logs em vários processos. Horário e URL ajudam, mas duas pessoas podem usar o sistema ao mesmo tempo. A correlação adiciona uma etiqueta única à operação para que seus registros possam ser encontrados sem expor o conteúdo da requisição.

## Fluxo síncrono

```text
Frontend
  → Gateway cria ou valida X-Correlation-ID
  → BFF preserva o valor
  → Frota, Operações, Identidade ou Indicadores preservam o valor
  → resposta volta com o mesmo UUID
```

O Gateway só aceita UUID. Assim, texto arbitrário enviado por um cliente não entra nos logs nem nas chamadas internas.

## Fluxo assíncrono

```text
requisição HTTP
  → Operações grava correlation_id na outbox
  → publicador inclui o valor no JSON e no cabeçalho RabbitMQ
  → Indicadores usa o cabeçalho em seus logs
  → Function usa correlationId do JSON em seus logs
```

Persistir na outbox é importante porque o evento pode ser publicado segundos ou minutos depois, quando a thread HTTP já não existe.

## Onde está o código

- `services/gateway/.../observability/CorrelationIdWebFilter.java`: valida, cria, encaminha e devolve o UUID.
- `services/*/.../observability/CorrelationIdFilter.java`: abre o MDC e registra a conclusão HTTP.
- `services/bff/.../observability/CorrelationIds.java`: propaga o valor nos clientes internos.
- `services/operacoes/.../observability/CorrelationIds.java`: propaga HTTP e fornece o UUID à outbox.
- `V5__correlacao_eventos.sql`: torna a correlação obrigatória na outbox.
- `RabbitPublicadorEventos.java`: adiciona o cabeçalho RabbitMQ.
- listeners de Indicadores e `NotificarAbastecimentoFunction.java`: restauram a correlação no consumo.

## Teste manual

Com o backend ativo, execute na raiz:

```powershell
$id = [guid]::NewGuid().ToString()
$resposta = Invoke-WebRequest `
  -UseBasicParsing `
  -Uri "http://127.0.0.1:8080/api/v1/ambiente" `
  -Headers @{ "X-Correlation-ID" = $id }

$resposta.StatusCode
$resposta.Headers["X-Correlation-ID"]
```

O resultado esperado é HTTP 200 e o mesmo UUID. Para procurá-lo nos logs:

```powershell
docker compose `
  --env-file ".env.sprint0" `
  -f "compose.sprint0.yaml" `
  -f "compose.sprint1-local.yaml" `
  -f "compose.jwt-rsa.yaml" `
  logs --since 5m gateway bff identidade frota operacoes indicadores |
  Select-String -SimpleMatch $id
```

Não pesquise ou copie o JWT para os logs. O UUID de correlação é suficiente.

## Consultar a outbox

Dentro do `psql` do banco Operações:

```sql
SELECT id, evento_tipo, correlation_id, publicado_em
FROM operacoes.outbox_evento
ORDER BY ocorrido_em DESC
LIMIT 10;
```

Uma linha nova deve ter `correlation_id` preenchido. Eventos existentes antes da V5 receberam o próprio `id` como fallback.

## Como interpretar

- mesmo UUID em vários serviços: a propagação funcionou;
- UUID diferente depois do Gateway: algum cliente HTTP não foi configurado para propagar;
- evento sem UUID: verifique a migração V5 e o adaptador JDBC;
- retry com o mesmo UUID: comportamento correto;
- valor inválido enviado pelo cliente e UUID novo na resposta: proteção funcionando.

A correlação ajuda a investigar; ela não prova identidade, não concede permissão e não evita duplicidade. JWT, autorização e idempotência continuam com responsabilidades separadas.
