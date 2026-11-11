# ADR 0020 — métricas Prometheus no ambiente local

- Estado: aceita para a primeira fatia da Sprint 4.
- Data: 07/11/2026.

## Contexto

O PJBL exige logs, métricas e correlação, além de Azure Monitor na publicação. Os serviços já possuíam Actuator e health checks, mas não havia coleta de séries temporais nem prova única de que todos os processos exportavam métricas.

## Decisão

Adicionar o registro Micrometer Prometheus aos seis processos Java. Cada processo expõe `/actuator/prometheus` na rede `application`; o API Gateway não roteia esse caminho. Um Prometheus LTS no Compose coleta os seis alvos a cada 15 segundos, mantém sete dias de dados e publica sua interface somente no loopback da máquina.

`Start-Local.ps1` chama `Test-Observability.ps1`, que consulta a API do Prometheus e exige os seis alvos com estado `UP`.

## Consequências

- Há uma base local e reproduzível para métricas de JVM, HTTP, pools e RabbitMQ.
- O volume de métricas é persistente, mas limitado a sete dias para não crescer indefinidamente.
- O endpoint não deve ganhar rota pública; em cloud, acesso e retenção precisam seguir a política do Azure Monitor/Application Insights.
- Esta decisão não conclui observabilidade: correlação de logs, alertas, métricas de lag e telemetria da Function ainda precisam de fatias próprias.

## Alternativas

- Apenas logs: insuficiente para tendências, p95 e capacidade.
- Publicar diretamente no Azure Monitor agora: descartado até confirmar assinatura, custos, região e segredos.
- Grafana nesta fatia: adiado; a interface e a API do Prometheus bastam para validar a coleta antes de definir dashboards operacionais.
