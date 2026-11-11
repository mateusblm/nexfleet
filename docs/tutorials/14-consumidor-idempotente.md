# Aula 14 — Consumidor idempotente em Indicadores

## O que é um consumidor

O produtor publica um fato e não precisa saber quem vai usá-lo. O consumidor fica ligado a uma fila, recebe a mensagem e executa uma reação. No NexFleet, Indicadores reage a `AbastecimentoRegistrado` criando uma projeção própria.

## O que é uma projeção

Uma projeção é uma cópia organizada para leitura. Operações continua sendo a fonte da verdade do abastecimento; Indicadores guarda apenas os campos necessários para calcular gastos e montar o dashboard. Não existe chave estrangeira entre os bancos.

## Por que a mensagem pode repetir

O RabbitMQ pode entregar novamente quando não recebe confirmação. Também pode ocorrer uma queda depois do banco confirmar e antes do ACK. Esse comportamento evita perda, mas exige que o consumidor suporte duplicatas.

## O que é idempotência

Uma operação idempotente pode ser repetida sem mudar o resultado depois da primeira execução. Aqui, `evento_id` é chave primária. O comando SQL usa `ON CONFLICT DO NOTHING`:

```sql
INSERT INTO indicadores.abastecimento_projecao (...)
VALUES (...)
ON CONFLICT DO NOTHING;
```

Na primeira entrega, uma linha é criada. Nas seguintes, o banco encontra a mesma chave e não altera nada.

## Clean Architecture na fatia

- `ProjetarAbastecimento`: valida o evento e decide se o resultado foi criado ou duplicado.
- `ProjecoesAbastecimento`: porta de persistência definida pela aplicação.
- `JdbcProjecoesAbastecimento`: adaptador PostgreSQL.
- `RabbitAbastecimentoListener`: adaptador de entrada do RabbitMQ.
- `RabbitTopologyConfig`: fila, exchange e binding pertencentes ao consumidor.

A camada `application` não importa Spring, RabbitMQ ou JDBC. O ArchUnit protege essa regra.

## Fluxo

```text
Operações/outbox → RabbitMQ → fila de Indicadores → listener → PostgreSQL Indicadores
```

O listener confirma a mensagem somente depois que sua transação termina. Se a gravação falhar, o RabbitMQ pode entregá-la novamente.

## Quando usar

Use idempotência em consumidores, webhooks, processamento de pagamentos e qualquer operação que possa ser repetida por retry. A chave deve identificar o fato original, não a tentativa de processamento.

## O que ainda falta

- retry limitado e DLQ foram acrescentados na v0.11.0; consulte a Aula 15;
- expor a projeção pela API de Indicadores;
- construir o dashboard no microfrontend Painel.
