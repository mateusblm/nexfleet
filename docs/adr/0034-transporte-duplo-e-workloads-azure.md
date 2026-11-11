# ADR 0034 — transporte duplo e workloads Azure

Data: 09/11/2026  
Estado: aceita para a preparação; publicação ainda não autorizada

## Contexto

O ambiente local do NexFleet já usa RabbitMQ e comprova retry, idempotência e DLQ. A Function planejada para Azure Flex Consumption, porém, deve consumir Azure Service Bus. Reescrever o ambiente local ou manter dois fluxos divergentes aumentaria o risco de regressão.

Também era necessário representar os seis serviços Java na Azure sem expor PostgreSQL à internet, sem credenciais do ACR e sem usar a tag `latest`.

## Decisão

1. RabbitMQ continua sendo o transporte local.
2. Azure Service Bus é o transporte da homologação Azure.
3. `MESSAGING_PROVIDER` seleciona o adaptador em Operações e Indicadores.
4. A Function possui dois gatilhos separados; somente o gatilho adequado ao ambiente é habilitado.
5. Identidades gerenciadas autenticam Operações como emissor, Indicadores e Function como receptores e os seis Container Apps no ACR.
6. O Bicep modela VNet, sub-redes delegadas, DNS privado e PostgreSQL sem acesso público.
7. As imagens usam a versão do arquivo `VERSION`; `latest` é proibido.
8. O adaptador Azure Communication Services Email existe, mas `captured-local` permanece o padrão até autorização explícita do provedor e dos destinatários.
9. Migrações de banco são executadas antes dos consumidores. A Function não executa Flyway durante o cold start.

## Consequências

- O domínio e os casos de uso não conhecem o broker concreto.
- O Compose local continua barato e reproduzível.
- A Azure usa RBAC e identidade gerenciada em vez de connection strings do Service Bus.
- A publicação ainda exige imagens no ACR, migrações, credenciais PostgreSQL por serviço, `what-if`, revisão de custo e autorização explícita.
- CQ09 e CQ10 precisam ser repetidos na infraestrutura realmente implantada.

## Alternativas rejeitadas

- Usar RabbitMQ na Function Flex Consumption: incompatível com o plano escolhido.
- Trocar o ambiente local inteiro por Service Bus: adicionaria custo e dependência de conta para desenvolvimento.
- Executar Flyway no cold start da Function: bloqueou o worker no ensaio integrado e mistura inicialização da infraestrutura com consumo de eventos.
- Ativar envio externo automaticamente: poderia enviar mensagens reais e gerar cobrança sem consentimento.
