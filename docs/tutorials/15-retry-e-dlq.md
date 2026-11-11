# Aula 15 — Retry limitado e DLQ

## O problema: a mensagem problemática

Uma mensagem problemática, às vezes chamada de *poison message*, é uma mensagem que o consumidor não consegue processar. Pode ser JSON inválido, campo obrigatório ausente ou contrato incompatível. Repetir para sempre não resolve um conteúdo definitivamente errado.

## O que é retry

Retry é tentar de novo depois de uma falha. Ele ajuda quando o problema é temporário, como uma breve indisponibilidade do banco. No NexFleet, o listener faz no máximo três tentativas. Há uma pequena espera crescente entre elas para não pressionar um recurso que já está falhando.

```text
tentativa 1 → espera 500 ms → tentativa 2 → espera 1 s → tentativa 3
```

## O que é DLQ

DLQ significa *Dead Letter Queue*, ou fila de mensagens que não puderam ser processadas. Depois que as tentativas acabam, o consumidor rejeita a mensagem. A fila principal informa ao RabbitMQ para onde encaminhá-la:

```text
fila principal → 3 falhas → dead-letter exchange → DLQ
```

A DLQ funciona como uma área de quarentena. Ela guarda a evidência da falha e permite que as próximas mensagens válidas continuem.

## Como foi implementado

- `application.properties` configura três tentativas e desativa o requeue infinito.
- `RabbitTopologyConfig` cria a fila principal com argumentos de dead-letter.
- Um `DirectExchange` recebe somente falhas com a chave definida.
- A DLQ é durável, portanto sua definição sobrevive ao reinício do broker.
- `RabbitTopologyConfigTest` verifica os argumentos e o binding sem depender do RabbitMQ em execução.
- `Test-Sprint2Eda.ps1` confirma que a fila principal possui consumidor e que a DLQ foi declarada.

## Quando usar

Use retry para falhas que podem desaparecer sozinhas. Use DLQ quando, após um limite razoável, a mensagem ainda falha e precisa de investigação. Nunca reprocesse uma DLQ em massa antes de corrigir a causa.

## O que ainda falta

- definir operação segura de inspeção e reprocessamento da DLQ;
- implementar registro e histórico de manutenções;
- expor a projeção de Indicadores por API e construir o dashboard;
- implementar a função serverless de notificação.
