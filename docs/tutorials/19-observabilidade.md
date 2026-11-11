# Aula 19 — métricas e Prometheus local

## O que foi acrescentado

O Actuator já respondia health checks. A v0.15.0 adiciona `micrometer-registry-prometheus`, que transforma as métricas internas do Spring Boot em séries no endpoint `/actuator/prometheus`. O Prometheus consulta esse endpoint periodicamente e armazena os valores ao longo do tempo.

## Por que usar

Um health check responde se o processo está pronto agora. Métricas permitem observar tendência: duração e quantidade de requisições, memória da JVM, threads, conexões e comportamento do broker. Isso prepara a medição de p95 e a investigação de incidentes sem registrar dados pessoais.

## Fluxo local

1. Cada serviço registra o nome da aplicação como tag comum.
2. O Prometheus resolve os nomes dos contêineres na rede `application`.
3. A cada 15 segundos, coleta `/actuator/prometheus`.
4. `Test-Observability.ps1` exige Gateway, BFF, Identidade, Frota, Operações e Indicadores em `UP`.
5. A interface local fica em `http://127.0.0.1:9090`.

Experimente a consulta:

```promql
up{job="nexfleet-java"}
```

O resultado esperado é uma série de valor `1` para cada um dos seis serviços.

## Limites de segurança

O Gateway não encaminha `/actuator/prometheus` para BFF ou serviços; a coleta desses alvos ocorre dentro do Compose. As próprias métricas do Gateway ficam acessíveis apenas pela porta 8080 ligada ao loopback, e a interface do Prometheus usa a porta 9090, também no loopback. Não publique esses endpoints na internet sem autenticação, rede privada e política de retenção.

## Próximas fatias

A correlação entre requisições e eventos foi entregue na v0.16.0 e está explicada na [Aula 20](20-correlacao-ponta-a-ponta.md). Alertas, métricas de lag, telemetria ampliada da Function e integração com Azure Monitor/Application Insights continuam na Sprint 4.
