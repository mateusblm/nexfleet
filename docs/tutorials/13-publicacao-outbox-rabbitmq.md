# Aula 13 — Publicação da outbox com RabbitMQ

## O problema

Na Aula 12, o abastecimento e o evento são gravados juntos no PostgreSQL. Isso garante que nunca exista abastecimento confirmado sem evento local, mas ainda falta entregar esse evento a outros serviços.

Publicar no RabbitMQ dentro da requisição seria perigoso. Se o broker aceitasse a mensagem e o banco falhasse depois, outros serviços receberiam um abastecimento inexistente. Se o banco confirmasse e o broker falhasse, o evento seria perdido.

## A solução

O padrão outbox separa os dois momentos:

1. A requisição grava abastecimento, hodômetro e outbox na mesma transação.
2. Depois, um job busca eventos com `publicado_em` vazio.
3. O job publica no RabbitMQ.
4. Somente após a confirmação do broker, o job marca o evento como publicado.

## Responsabilidade de cada classe

- `PublicarEventosPendentes`: caso de uso puro; decide sucesso, falha e retry.
- `EventosOutbox`: porta para consultar e atualizar eventos.
- `PublicadorEventos`: porta para qualquer broker.
- `JdbcEventosOutbox`: adaptador PostgreSQL.
- `RabbitPublicadorEventos`: adaptador RabbitMQ e `publisher confirm`.
- `OutboxPublicacaoJob`: agenda os lotes e abre a transação que mantém o lock.
- `RabbitTopologyConfig`: declara exchange, fila e binding duráveis.

## Por que usar FOR UPDATE SKIP LOCKED

`FOR UPDATE` bloqueia as linhas selecionadas durante o lote. `SKIP LOCKED` manda outra instância ignorar essas linhas em vez de esperar. Isso permite escalar o publicador sem duas instâncias trabalharem simultaneamente no mesmo evento.

## O que significa pelo menos uma vez

O sistema prefere repetir uma mensagem a perdê-la. Se o processo cair depois da confirmação do RabbitMQ e antes do commit do PostgreSQL, a linha ainda parecerá pendente e poderá ser publicada de novo. Por isso, o consumidor futuro deverá guardar o `eventoId` e ignorar repetições.

## Retry e disponibilidade

Quando o broker falha, a linha continua com `publicado_em` vazio. O sistema incrementa `tentativas`, registra `ultimo_erro` e define `proxima_tentativa_em`. A API permanece saudável porque registrar um abastecimento depende do banco local, não da disponibilidade imediata do broker.

## Como observar localmente

Suba o projeto e acesse `http://127.0.0.1:15672`. Use `RABBITMQ_USER` e `RABBITMQ_PASSWORD` de `.env.sprint0`. A partir da v0.11.0, a fila principal `nexfleet.indicadores.projecao-abastecimentos.v1.com-dlq` pertence ao consumidor de Indicadores e possui uma DLQ vinculada.

## Quando usar

Use outbox quando um fato persistido precisa ser comunicado com segurança a outros processos. Não use para chamadas síncronas que precisam de resposta imediata do outro serviço. No NexFleet, validar um vínculo usa HTTP; comunicar um abastecimento concluído usa evento.

## O que ainda falta

- política de DLQ após esgotar tentativas;
- função serverless de notificação;
- métricas e alertas da fila.
