# Aula 33 — transporte duplo e workloads Azure

## 1. O problema

Localmente, o NexFleet usa RabbitMQ. Na Azure, o plano Flex Consumption da Function combina melhor com Service Bus. A solução não é duplicar regra de negócio: apenas o adaptador de transporte muda.

```text
Operações -> PublicadorEventos -> RabbitMQ   (local)
                              -> Service Bus (Azure)

RabbitMQ/Service Bus -> Indicadores -> projeções
RabbitMQ/Service Bus -> Function -> notificação auditável
```

## 2. Seleção por configuração

No Compose, `MESSAGING_PROVIDER=rabbitmq`. Nos Container Apps, o Bicep define `MESSAGING_PROVIDER=servicebus`. As classes RabbitMQ são condicionais e os clientes Azure usam `DefaultAzureCredential` com o `AZURE_CLIENT_ID` da identidade do workload.

Isso mantém a aplicação igual: a outbox continua sendo confirmada somente depois que o adaptador publica com sucesso.

## 3. Service Bus

O namespace contém o tópico `nexfleet-eventos-v1` e duas assinaturas:

- `indicadores-v1`: abastecimentos e manutenções;
- `notificacoes-abastecimentos-v1`: somente abastecimentos.

As propriedades `eventType`, `eventVersion` e `correlationId` permitem filtragem e rastreabilidade. A entrega pode repetir; por isso Indicadores e Notificações continuam idempotentes.

## 4. Function e e-mail

A Function empacota dois gatilhos, mas o ambiente habilita somente um. No local, ela grava a solicitação no PostgreSQL com `EMAIL_PROVIDER=captured-local`. O adaptador `azure-communication` só deve ser habilitado depois de criar o recurso, validar remetente/domínio, definir destinatários autorizados e aceitar o custo.

A migração do banco não roda dentro da Function. Ela deve terminar antes de o gatilho ser habilitado, evitando bloquear o cold start.

## 5. Workloads no Bicep

O modelo contém:

- seis Container Apps com imagens versionadas;
- uma identidade gerenciada por serviço;
- permissão ACR Pull para cada identidade;
- papéis de envio/recepção mínimos no Service Bus;
- VNet com sub-redes para Container Apps, PostgreSQL e Function;
- DNS privado e PostgreSQL sem rede pública;
- Function Flex, APIM, Static Web Apps e observabilidade.

`publicationApproved=false` e `workloadsEnabled=false` impedem uma criação acidental. O repositório ainda não possui comando de deploy.

## 6. Como verificar sem implantar

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\Test-AzureInfrastructure.ps1
```

Resultado esperado: `19 tipos modelados, 0 pendente e nenhum comando de implantação`.

Para montar o frontend Azure sem publicar:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\Build-AzureFrontend.ps1 `
  -ApiBaseUrl "https://SEU-APIM.azure-api.net"
```

O pacote fica em `output/azure-web`.

## 7. O que falta para a nuvem

Antes da implantação: revisar cotas/preços, criar usuários PostgreSQL por serviço, definir a etapa de migração, publicar imagens e pacote da Function, autorizar e configurar e-mail, executar/revisar o `what-if` e obter autorização explícita para criar workloads pagos.

Depois da implantação: validar HTTPS, segredos, RBAC, DLQs, custos, backup/PITR e repetir CQ09/CQ10.
