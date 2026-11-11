# NexFleet v0.11.0 — retry limitado e DLQ

## Entregue

- Até três tentativas no listener de Indicadores.
- Espera progressiva entre tentativas.
- Dead-letter exchange e DLQ duráveis.
- Fila principal configurada para encaminhar mensagens esgotadas.
- Testes unitários da topologia RabbitMQ.
- Verificação local da fila principal, consumidor e DLQ.
- ADR 0016 e Aula 15.

## Critério de aceitação

- Mensagem válida continua criando uma única projeção, mesmo repetida.
- Mensagem inválida sai da fila principal depois de três falhas.
- Mensagem inválida permanece disponível na DLQ.
- O consumidor continua conectado para processar mensagens seguintes.

## Evidências locais

- 150 testes backend aprovados, sem falhas ou erros.
- 42 testes frontend aprovados e quatro builds Vite concluídos.
- Onze contêineres saudáveis e Gateway respondendo `UP`.
- Mensagem inválida rejeitada após esgotar o retry e preservada na DLQ com cabeçalho `x-death`.
- Fila principal vazia e com um consumidor conectado após a falha.
- Duas entregas do mesmo evento válido criaram uma única projeção em Indicadores.

## Ainda pendente na Sprint 2

- registro e histórico de manutenções.

Dashboard, função serverless e publicação Azure permanecem em sprints posteriores. A Sprint 2 ainda não está concluída.
