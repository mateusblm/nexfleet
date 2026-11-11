# Entrega v0.14.0 — Function serverless e conclusão local da Sprint 3

## Resultado

A Sprint 3 está concluída no ambiente local. Além do dashboard da v0.13.0, o NexFleet possui uma Azure Function Java 21 acionada pelo evento de abastecimento, idempotência por evento e isolamento de falhas em DLQ.

## Componentes adicionados

- `functions/notificar-abastecimento`: Function com Clean Architecture e Vertical Slice;
- `notificacoes-migrations`: Flyway executado antes do runtime;
- `notificacoes-db`: estado idempotente exclusivo da função;
- `rabbitmq-topology`: fila quorum, limite de entregas, DLX e DLQ;
- `azurite`: armazenamento interno local do host Azure Functions;
- `Test-Sprint3Serverless.ps1`: prova integrada de duplicata e falha.

## Verificação executada em 06/11/2026

- build da imagem Azure Functions Java 21 aprovado;
- 3 testes do caso de uso e 3 testes ArchUnit aprovados;
- host encontrou e iniciou `Host.Functions.NotificarAbastecimento`;
- Azurite recebeu e manteve o lease do host sem erro de armazenamento;
- evento publicado duas vezes resultou em uma única linha por `evento_id`;
- JSON inválido foi reentregue até o limite e encaminhado à DLQ;
- Flyway foi retirado do cold start e executado como etapa anterior ao deploy.

## Limites preservados

O adaptador local registra a solicitação, mas não envia mensagem externa. Destinatário, domínio remetente, provedor, consentimento e credenciais não constam no PJBL e serão definidos na Sprint 4. Nenhum recurso Azure foi provisionado nesta versão.
