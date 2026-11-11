#!/bin/sh
set -eu

tentativa=1
until rabbitmqadmin --quiet show overview >/dev/null 2>&1; do
  if [ "$tentativa" -ge 30 ]; then
    echo "A API de administracao do RabbitMQ nao ficou pronta em 30 segundos." >&2
    exit 1
  fi
  tentativa=$((tentativa + 1))
  sleep 1
done

rabbitmqadmin declare exchange \
  --name nexfleet.eventos --type topic --durable true --auto-delete false
rabbitmqadmin declare exchange \
  --name nexfleet.eventos.dlx --type direct --durable true --auto-delete false

rabbitmqadmin declare queue \
  --name nexfleet.notificacoes.abastecimentos.v1 \
  --type quorum --durable true --auto-delete false \
  --arguments '{"x-delivery-limit":3,"x-dead-letter-exchange":"nexfleet.eventos.dlx","x-dead-letter-routing-key":"notificacoes.abastecimento.falha.v1"}'
rabbitmqadmin declare queue \
  --name nexfleet.notificacoes.abastecimentos.v1.dlq \
  --type classic --durable true --auto-delete false

rabbitmqadmin declare binding \
  --source nexfleet.eventos --destination-type queue \
  --destination nexfleet.notificacoes.abastecimentos.v1 \
  --routing-key operacoes.abastecimento.registrado.v1
rabbitmqadmin declare binding \
  --source nexfleet.eventos.dlx --destination-type queue \
  --destination nexfleet.notificacoes.abastecimentos.v1.dlq \
  --routing-key notificacoes.abastecimento.falha.v1
