# Entrega NexFleet v0.29.0

Data: 09/11/2026

## Resultado

A preparação técnica Azure da Sprint 4 foi concluída sem criar workloads pagos. O código agora suporta RabbitMQ local e Service Bus na Azure, a Function possui os dois gatilhos, o Bicep modela 19/19 famílias de recursos e os frontends podem ser empacotados para Static Web Apps.

A Sprint 4 completa ainda depende da publicação real e de validações em homologação. O estado não é chamado de concluído enquanto HTTPS, custo, segurança, backup, CQ09 e CQ10 não forem comprovados na Azure.

## Implementado

- Publicador Service Bus em Operações com identidade gerenciada.
- Consumidor Service Bus em Indicadores, mantendo RabbitMQ local.
- Gatilho Service Bus na Azure Function e gatilho RabbitMQ local.
- Adaptador opcional de Azure Communication Services Email.
- Migração V2 do banco de Notificações com estado e auditoria da entrega.
- VNet, DNS privado, PostgreSQL privado, seis Container Apps e RBAC em Bicep.
- 19 tipos de recursos modelados e zero pendências estruturais no inventário.
- URL de API configurável e pacote dos quatro frontends para Static Web Apps.
- Proteções `publicationApproved=false` e `workloadsEnabled=false`.

## Verificações executadas

| Verificação | Resultado |
|---|---|
| Serviços Java | 176 testes aprovados |
| Azure Function | 8 testes aprovados e pacote com dois gatilhos |
| Frontends | 47 testes e quatro builds aprovados |
| Bicep | 19 tipos modelados, 0 pendente, lint/build aprovados |
| EDA local | consumidores e DLQs declarados |
| Serverless local | evento duplicado persistido uma vez; inválido enviado à DLQ |
| Compose | Gateway e dependências saudáveis após a validação |

## Correção importante

Uma tentativa de executar Flyway durante a inicialização estática da Function bloqueou o worker. A alteração foi revertida e o fluxo integrado voltou a passar. Migrações continuam sendo uma etapa independente, executada antes do consumidor, evitando aumentar o cold start e misturar responsabilidades.

## Como executar no Windows

Na raiz do projeto:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\Start-Local.ps1
```

Na primeira execução, use `-ProvisionUser`. Depois inicie shell e microfrontends conforme `docs/GUIA-EXECUCAO-LOCAL.md` e abra `http://127.0.0.1:5173`.

## Como executar no MacBook

Instale Docker Desktop, Node.js 24 e JDK 21. Na raiz:

```bash
docker compose --env-file .env.sprint0 \
  -f compose.sprint0.yaml \
  -f compose.jwt-rsa.yaml up -d --build
```

Depois, em quatro terminais, execute `npm install` na primeira vez e `npm run dev` em `frontend`, `microfrontends/frota`, `microfrontends/operacoes` e `microfrontends/painel`. O roteiro completo, incluindo geração da chave RSA, permissões e solução de problemas, está em `docs/GUIA-EXECUCAO-MACOS.md`.

## Pendências para concluir a Sprint 4

1. Revisar cotas e estimativa real de custo. R$ 100 é alerta, não limite de cobrança.
2. Substituir o login administrativo temporário do PostgreSQL por usuário/papel próprio de cada serviço.
3. Definir e executar migrações antes de habilitar os workloads.
4. Executar e revisar o `what-if` com imagens versionadas disponíveis.
5. Autorizar explicitamente a criação dos workloads pagos.
6. Autorizar/configurar Azure Communication Services Email, remetente e destinatários; nenhum e-mail real foi enviado.
7. Publicar frontend, APIM, serviços e Function por HTTPS.
8. Repetir CQ09 e CQ10 na homologação e validar alertas, backup/PITR, DLQs e observabilidade.

## Custos

O orçamento atual de R$ 100/mês é conservador e pode ser menor que a soma dos recursos planejados, especialmente PostgreSQL, Service Bus Standard e ACR. Créditos estudantis e franquias podem reduzir o valor efetivo, mas não devem ser presumidos antes do `what-if` e da consulta de preços/cotas da assinatura.
