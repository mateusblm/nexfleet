# Aula 32 — provedores, orçamento e próximos passos Azure

## 1. Por que registrar um provedor

Um namespace como `Microsoft.DBforPostgreSQL` habilita aquele tipo de serviço na assinatura. Registrar o provedor não cria banco nem gera uma carga de trabalho, mas altera a configuração da assinatura; por isso o NexFleet exige `-Authorize` e usa uma lista fixa.

```powershell
./scripts/Register-AzureProviders.ps1 -Authorize
```

O script é idempotente: ignora quem já está `Registered`, repete falhas transitórias e confere o estado antes de tentar novamente.

## 2. Por que criar o orçamento antes dos serviços

O orçamento torna o custo visível desde o começo. O NexFleet usa R$ 100/mês e envia alertas quando o gasto real atinge 50% e 80%, além de alertar quando a previsão chega a 100%.

```powershell
./scripts/Set-AzureBudget.ps1 -Authorize
```

O orçamento não bloqueia nem desliga recursos. Quando um alerta chegar, a equipe deve revisar o Cost Management e parar/remover manualmente o que não deve continuar.

## 3. Por que duas regiões

Os serviços de backend e dados ficam em `Brazil South`, reduzindo distância para o uso brasileiro. O Static Web Apps usa `East US 2` porque esse tipo possui uma lista própria de regiões. Isso não move o PostgreSQL para os Estados Unidos.

## 4. Service Bus e RabbitMQ

RabbitMQ continua sendo o transporte local. Na Azure, Service Bus foi aprovado para a mensageria gerenciada. A v0.29.0 implementou os adaptadores em Operações, Indicadores e Function, preservando idempotência, correlação e DLQ. A próxima prova ocorre somente depois de uma implantação autorizada.

## 5. E-mail recomendado

Azure Communication Services Email encaixa-se no ecossistema escolhido e cobra por uso. O domínio gerenciado pela Azure é adequado para primeiros testes; produção deve usar domínio próprio verificado por DNS, SPF e DKIM.

A recomendação não cria o recurso. Ainda é necessário aprovar o namespace `Microsoft.Communication`, o remetente/domínio, os destinatários permitidos e o tratamento de consentimento e descadastro.

## 6. Estado seguro atual

Os cinco provedores e o orçamento estão prontos. O Bicep da v0.29.0 modela rede, dados, Service Bus, seis Container Apps, Function, APIM e frontend, mas a trava de publicação permanece fechada. Não há grupo de recursos, PostgreSQL, Service Bus, Container Apps, Function, APIM ou frontend implantado.

O próximo passo seguro é revisar cotas e preços, separar credenciais PostgreSQL, definir a migração cloud, fechar a decisão de e-mail, executar o preflight conectado e só então autorizar um `what-if`. O `what-if` mostra uma previsão; ainda não publica nada.
