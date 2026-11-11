# Entrega v0.17.0 — contratos executáveis e smoke E2E

## Resultado

A terceira fatia da Sprint 4 transforma os contratos HTTP e de eventos em uma barreira automática de qualidade e adiciona um smoke test integrado que percorre os componentes reais sem criar dados de Frota ou Operações no banco local.

## Componentes entregues

- contrato OpenAPI novo para abastecimentos;
- respostas completas e `operationId` nos contratos existentes;
- AsyncAPI para `AbastecimentoRegistrado.v1` e `ManutencaoRegistrada.v1`;
- projeto Maven independente `quality` com dois testes;
- validação de chaves duplicadas, `$ref`, segurança, parâmetros, respostas e rotas;
- `Test-ApiContracts.ps1` para autenticação e APIs reais;
- `Test-E2E.ps1` para API, EDA, Function, DLQ e Prometheus;
- evento serverless de teste compatível com o contrato atual;
- validação de contratos no workflow de backend;
- workflow E2E com bancos, segredos e volumes efêmeros.

## Segurança e dados

As credenciais são lidas do `.env.sprint0` e não aparecem na saída. O smoke HTTP apenas consulta os dados existentes. A prova serverless cria uma notificação identificada por UUID aleatório e uma entrada controlada na DLQ; não cadastra veículo, motorista, abastecimento ou manutenção.

Na CI, a configuração inteira é efêmera e `down --volumes` é executado mesmo em caso de falha.

## Verificação

- 2 testes de contrato aprovados;
- 10 OpenAPI e 1 AsyncAPI carregados sem chave duplicada ou referência quebrada;
- 172 testes dos seis serviços Java aprovados;
- 8 testes da Azure Function aprovados;
- 43 testes frontend e quatro builds Vite aprovados;
- login, sessão, autorização, Frota, Operações e Dashboard validados pelo Gateway;
- consumidores, DLQs, idempotência da Function e Prometheus validados no Compose.

A Sprint 4 continua em andamento. Permanecem as evidências formais de usabilidade/desempenho/recuperação, revisão dos diagramas, decisão de e-mail externo e publicação Azure aprovada.
