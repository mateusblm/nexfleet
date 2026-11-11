# ADR 0019 — Função serverless de notificação

## Contexto

O PJBL exige uma função serverless que reaja ao registro de abastecimento, seja idempotente e tolere falhas. O comando de abastecimento já grava `AbastecimentoRegistrado.v1` na outbox e o publica no RabbitMQ depois do commit. O documento não informa destinatário, domínio remetente ou provedor de e-mail.

## Decisão

- Criar uma Azure Function Java 21 chamada `NotificarAbastecimento`, acionada pela fila `nexfleet.notificacoes.abastecimentos.v1`.
- Manter a fatia `notificarabastecimento` separada em `api`, `application` e `infrastructure`. A aplicação define a porta `ProvedorEmail`; o adaptador local não invade o caso de uso.
- Usar `eventoId` como chave de idempotência e chave primária no banco próprio de notificações. `INSERT ... ON CONFLICT DO NOTHING` torna a repetição segura.
- No ambiente local, capturar a solicitação em PostgreSQL. Isso comprova assunto, corpo, auditoria e duplicata sem declarar falsamente que um e-mail externo foi entregue.
- Usar uma fila quorum com `x-delivery-limit=3`, dead-letter exchange e DLQ. A Function lança exceção para evento inválido; o broker controla a repetição e o isolamento final.
- Executar Flyway como etapa anterior à Function. Migração durante o primeiro evento aumenta cold start e permite concorrência indesejada entre instâncias.
- Usar Azurite como `AzureWebJobsStorage` no Docker local. Na Azure, a configuração apontará para uma Storage Account real.
- Adiar a escolha do provedor externo. Na publicação, outro adaptador poderá implementar `ProvedorEmail` sem alterar o caso de uso.

## Consequências

O abastecimento continua independente da notificação: uma falha de e-mail não desfaz o registro operacional. Reentregas são esperadas e seguras. Mensagens problemáticas ficam visíveis na DLQ. O banco de notificações pertence ao implantável da Function e não é consultado por outros serviços.

O ambiente local comprova a solicitação, não a entrega em uma caixa postal. Para produção ainda será necessário definir destinatário, consentimento, remetente, provedor, segredos, telemetria e política de reprocessamento da DLQ. O binding RabbitMQ da Azure Functions tem restrições de hospedagem; a Sprint 4 deverá validar o plano ou trocar o transporte externo por Service Bus, preservando o caso de uso.

## Alternativas consideradas

- Enviar e-mail dentro de Operações: rejeitado porque acopla uma integração lenta ao comando principal.
- Considerar cada mensagem como nova: rejeitado porque brokers trabalham com entrega pelo menos uma vez.
- Executar Flyway no cold start: rejeitado após o teste demonstrar que a primeira invocação pode ficar ocupada com infraestrutura.
- Inventar um destinatário local: rejeitado porque o PJBL não define essa regra.
