# ADR 0021 — correlação ponta a ponta

- Estado: aceita para a segunda fatia da Sprint 4.
- Data: 07/11/2026.

## Contexto

As métricas da v0.15.0 mostram tendências e disponibilidade, mas não permitem reconstruir facilmente uma operação que atravessa Gateway, BFF, microsserviços, outbox, RabbitMQ e Function. Usar conteúdo livre fornecido pelo cliente criaria risco de falsificação e injeção em logs. Registrar corpos, tokens ou dados pessoais para localizar uma chamada também seria inadequado.

## Decisão

Usar `X-Correlation-ID` com um UUID canônico por operação.

1. O Gateway aceita apenas um UUID com 36 caracteres. Valor ausente ou inválido é substituído por um UUID aleatório.
2. O Gateway encaminha o valor ao BFF e o devolve uma única vez na resposta.
3. BFF e Operações propagam o identificador em todos os clientes HTTP internos construídos pela aplicação.
4. Gateway, BFF, Identidade, Frota, Operações e Indicadores registram o valor no MDC e em logs de conclusão com método, caminho, status e duração.
5. A migração V5 acrescenta `correlation_id UUID NOT NULL` à outbox. Linhas antigas recebem o próprio `id` do evento.
6. Eventos novos incluem `correlationId` no JSON e `X-Correlation-ID` no cabeçalho RabbitMQ.
7. Indicadores usa o cabeçalho da mensagem; a Azure Function usa o payload. Eventos antigos sem a nova informação usam `messageId` ou `eventoId` como fallback.

Os logs desta fatia não incluem query string, corpo, cabeçalho `Authorization`, JWT, senha, CPF, CNH, descrição, oficina, valores ou outros dados de negócio.

## Consequências

- Uma operação pode ser pesquisada pelo mesmo UUID em todos os serviços e consumidores.
- A correlação sobrevive ao fim da requisição HTTP porque é persistida na outbox.
- Retry e redelivery preservam o identificador original.
- A mudança de evento é aditiva e compatível com mensagens v1 já gravadas.
- As pequenas classes de observabilidade são locais a cada deployável para manter os serviços independentes; não foi criado um módulo compartilhado obrigatório.
- Correlação não substitui autenticação, trace distribuído, métricas, auditoria de negócio ou idempotência.

## Alternativas

- Aceitar qualquer texto do cliente: rejeitado por risco de conteúdo arbitrário em logs e cabeçalhos internos.
- Usar somente `eventoId`: insuficiente antes da criação do evento e nas consultas HTTP sem evento.
- Registrar token ou corpo da requisição: rejeitado por segurança e privacidade.
- Introduzir OpenTelemetry completo nesta fatia: adiado; exige coletor, exportador, política de amostragem e destino de cloud ainda não aprovados.
