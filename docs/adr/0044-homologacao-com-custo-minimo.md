# ADR 0044 — Homologação Azure com custo mínimo

Data: 11/11/2026
Estado: aceita

## Contexto

A homologação da v0.30.0 (ADR 0037) usava PostgreSQL Flexible Server privado, ACR, zona DNS privada e Container Apps com réplicas mínimas acima de zero em parte dos serviços. Com isso, o crédito mensal da assinatura (US$ 100) acabaria rapidamente. A v1.0.0 precisava continuar publicada, com o mesmo fluxo funcional.

## Decisão

1. **Removidos do Bicep:** PostgreSQL Flexible Server, zona DNS privada `privatelink.postgres.database.azure.com` e o link, ACR e os papéis `AcrPull`, e os jobs de migração (`migration-job.bicep`). Como o modo incremental não apaga nada, os recursos antigos foram excluídos à mão depois do smoke. A sub-rede `postgresql` continua declarada enquanto `legacyPostgresqlSubnetEnabled=true`, porque uma sub-rede em uso não pode ser removida.
2. **Banco gratuito:** Azure SQL Database serverless `GP_S_Gen5_2` com `useFreeLimit: true`, `freeLimitExhaustionBehavior: 'AutoPause'` e `autoPauseDelay: 60` (ADR 0040). Frota no MongoDB Atlas M0, gratuito (ADR 0039).
3. **Escala a zero:** os seis Container Apps têm `minReplicas: 0`. Indicadores acorda por uma regra KEDA `azure-servicebus` na assinatura `indicadores-v1`; a Function de notificação escala por evento no Flex Consumption.
4. **Imagens do Docker Hub** no lugar do ACR (ADR 0042).
5. **Serviços cobrados por uso:** APIM Consumption, Function Flex Consumption, Static Web Apps Free e Log Analytics com limite diário de 0,15 GB.
6. **Único custo fixo:** Service Bus **Standard**, mantido porque os tópicos e assinaturas com regras (ADR 0037) exigem esse tier. A estimativa da spec é de cerca de R$ 60/mês; `scripts/Get-AzureCostEstimate.ps1` recalcula pela API pública de preços. O orçamento de R$ 100/mês continua só como alerta.
7. **AsyncAPI no cliente:** a página `/docs/eventos` é servida pelo Static Web Apps, sem serviço extra. O web component AsyncAPI fica no próprio site (`/docs/eventos/vendor/`). A CSP dessas rotas acrescenta `'unsafe-eval'` em `script-src`, porque o parser valida o contrato com Ajv, que compila validadores com `new Function`. A exceção vale só para `/docs/eventos` e `/docs/eventos/*`; o restante do site mantém `script-src 'self'`.

## Consequências

- **Partida a frio de ~1 a 2 min.** Depois de um tempo parado, os Container Apps estão em zero réplicas e o banco pode estar pausado. A primeira chamada pode receber 502, 503 ou 504 enquanto a réplica sobe e o banco retoma. No smoke a frio de 11/11/2026, o login levou cerca de 90 s (Identidade + retomada do SQL). **Antes de uma demonstração, aqueça o ambiente:** `scripts/smoke-publico.sh` já faz isso, chamando login, Frota, Operações e Indicadores até responderem.
- **Risco conhecido: um POST que recebe 503 na partida a frio pode ter sido gravado.** O Gateway e o BFF podem estourar o tempo antes de o serviço de destino responder, mas o serviço conclui a gravação. Repetir a requisição pode gerar 409 (placa, CPF ou CNH já existentes) ou um registro duplicado. Por isso o smoke só repete GET e login; para a demonstração, consulte a lista antes de repetir um cadastro.
- **Eventos com Operações em zero réplicas:** o publicador da outbox roda dentro do app. Com zero réplicas, os eventos só saem enquanto Operações está ativo; como todo registro chega por HTTP, o app fica ativo alguns minutos depois dele e publica.
- **Limite gratuito do SQL:** se o limite mensal se esgotar, o banco pausa até o mês seguinte e o sistema fica indisponível, em vez de gerar cobrança.
- **`'unsafe-eval'` em `/docs/eventos`:** um script injetado nessa página poderia usar `eval`. A página só tem conteúdo estático do próprio site, não recebe dados do usuário e não tem sessão, porque o token fica em memória no shell.
- As provas CQ09 (desempenho com perfil `carga`) e CQ10 (restauração point-in-time do PostgreSQL) são da v0.30.0 e não foram repetidas nesta infraestrutura.

## Alternativas rejeitadas

- **`minReplicas: 1` em Identidade, BFF e Gateway:** elimina a partida a frio do login, mas cobra 24 h por dia. Pode ser ligado só no dia da apresentação (`az containerapp update --min-replicas 1`) e revertido depois.
- **Service Bus Basic:** não tem tópicos; exigiria trocar a topologia de eventos (fora do escopo da spec).
- **Renderizar o AsyncAPI no servidor:** exigiria um serviço a mais ou um passo de build com navegador; a exceção de CSP limitada a `/docs/eventos` é menor.
