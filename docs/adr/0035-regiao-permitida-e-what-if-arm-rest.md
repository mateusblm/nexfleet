# ADR 0035 — região permitida e what-if via ARM REST

Data: 10/11/2026  
Estado: aceita para a preparação; implantação ainda não autorizada

## Contexto

A política `sys.regionrestriction` da assinatura Azure for Students recusou as regiões originalmente planejadas, `Brazil South` e `East US 2`. A consulta conectada mostrou cinco regiões permitidas: `Central US`, `Chile Central`, `Mexico Central`, `North Central US` e `Spain Central`. Entre elas, somente `Central US` oferece os 19 tipos necessários em uma única região.

Depois da aprovação do usuário para escolher qualquer região compatível, o Azure CLI iniciou o `what-if`, mas a conexão longa foi repetidamente encerrada com `ConnectionResetError 10054`. Consultas curtas continuaram funcionando e nenhum grupo de recursos foi criado.

## Decisão

1. Usar `Central US` para backend, dados e Static Web Apps da homologação.
2. Manter `location` e `staticWebLocation` separados no perfil e no Bicep, mesmo quando possuem o mesmo valor.
3. Oferecer dois transportes no executor: `AzureCli` e `ArmRest`.
4. Usar o endpoint oficial `whatIf` no escopo da assinatura como alternativa para operações longas.
5. Acompanhar respostas `202 Accepted` pela URL `Location`, respeitando `Retry-After` e um prazo máximo.
6. Manter `ProviderNoRbac` como validação completa recomendada e `ResourceIdOnly` como formato do relatório.
7. Gravar somente `status`, `resourceId` e `changeType`, ocultar parâmetros seguros em erros e remover todos os temporários.
8. Reprovar qualquer resultado diferente de `Succeeded` ou que contenha exclusões.

## Evidência

Em 10/11/2026, o `what-if` `ProviderNoRbac` via ARM REST terminou com `Succeeded`: 62 recursos previstos como `Create`, uma implantação lógica como `Deploy` e zero `Delete`. O relatório local é ignorado pelo Git. A operação não criou recursos e não concede autorização para implantação.

## Consequências

- A homologação possui uma região compatível e aprovada.
- A previsão pode ser concluída mesmo quando o processo Python do Azure CLI perde uma conexão longa.
- O fluxo continua reproduzível no Windows PowerShell 5.1 e no PowerShell 7.
- Mudanças materiais no Bicep exigem novo `what-if`.
- Cotas, credenciais dos bancos, migrações, pacotes, e-mail e autorização de cobrança continuam pendentes.

## Alternativas rejeitadas

- Insistir em `Brazil South` ou `East US 2`: a política da assinatura recusa essas regiões.
- Dividir backend e frontend entre Chile e Estados Unidos: adicionaria complexidade sem necessidade, pois `Central US` atende os 19 tipos.
- Tratar falha de conexão como aprovação: não produz evidência verificável.
- Executar implantação para testar o template: criaria recursos e custo antes das aprovações restantes.

## Referências

- [What-if no escopo da assinatura](https://learn.microsoft.com/rest/api/resources/deployments/whatifatsubscriptionscope)
- [Operações assíncronas do Azure Resource Manager](https://learn.microsoft.com/azure/azure-resource-manager/management/async-operations)
