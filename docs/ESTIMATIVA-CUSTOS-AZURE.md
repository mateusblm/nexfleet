# Estimativa de custos da homologação Azure

Atualização: 10/11/2026.

## Resultado

A arquitetura Azure completa atualmente modelada não cabe em R$ 100 por mês sem créditos, franquias ou mudanças de desenho. A consulta reproduzível à API pública de preços encontrou esta faixa parcial para a região aprovada, `Central US`:

| Componente | Estimativa mensal |
|---|---:|
| PostgreSQL Flexible Server B1ms — computação | R$ 75,41 |
| PostgreSQL — 32 GiB | R$ 22,36 |
| Service Bus Standard — unidade base | R$ 53,76 |
| Container Registry Basic | R$ 27,26 |
| Container Apps — três réplicas mínimas ociosas | R$ 182,02 |
| Container Apps — três réplicas mínimas ativas | R$ 606,72 |
| **Faixa parcial total** | **R$ 360,81 a R$ 785,51** |

A faixa inferior presume que as três réplicas mínimas permanecem ociosas e que as franquias mensais de Container Apps estão integralmente disponíveis. A referência superior considera essas réplicas ativas durante as 730 horas do mês. Serviços Java com processamento em segundo plano podem ultrapassar o limiar de ociosidade.

## O que está incluído

- PostgreSQL `Standard_B1ms` ligado por 730 horas.
- Armazenamento PostgreSQL de 32 GiB.
- Unidade base do Service Bus Standard.
- ACR Basic por 30,4375 dias.
- Três réplicas mínimas do Bicep: Operações, Indicadores e Gateway, cada uma com 0,5 vCPU e 1 GiB.
- Franquia mensal de 180.000 vCPU-segundos e 360.000 GiB-segundos do Container Apps presumida disponível.

## O que não está incluído

- Log Analytics e Application Insights acima das franquias.
- Chamadas do API Management, Function, Storage e Key Vault.
- Private DNS, transferência de dados, impostos e variação cambial.
- Réplicas adicionais acionadas pelo autoscaling.
- Azure Communication Services Email.
- Descontos, créditos ou benefícios da assinatura Azure for Students.

Por isso, a faixa é uma referência de planejamento, não uma cotação nem um teto de cobrança. A própria Microsoft informa que os preços publicados são estimativas e podem variar conforme oferta, contrato, data e câmbio. Consulte a [API Azure Retail Prices](https://learn.microsoft.com/rest/api/cost-management/retail-prices/azure-retail-prices), a [calculadora de preços](https://learn.microsoft.com/azure/cost-management-billing/costs/pricing-calculator), a [cobrança de Container Apps](https://learn.microsoft.com/azure/container-apps/billing) e a [página de preços do PostgreSQL Flexible Server](https://azure.microsoft.com/pricing/details/postgresql/flexible-server/).

## Como atualizar a estimativa

No PowerShell, na raiz do projeto:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\scripts\Get-AzureCostEstimate.ps1" `
  -OutputPath ".\infra\azure\cost-estimate-atual.json"
```

O script:

1. lê região, moeda e orçamento do perfil local;
2. lê CPU, memória e `minReplicas` diretamente do Bicep;
3. consulta somente a API pública de preços da Azure;
4. calcula os cenários ocioso e ativo;
5. não acessa a conta Azure, não cria recursos e não altera a assinatura.

O JSON gerado é evidência local e não contém credenciais.

## Decisão recomendada

Enquanto não houver uma implantação curta e controlada para medir o consumo real, o orçamento de R$ 100 deve continuar servindo como alerta antecipado. Ele não interrompe serviços nem limita cobrança.

Antes de autorizar workloads pagos, escolha uma destas estratégias:

1. manter a arquitetura atual e aprovar uma referência inicial de até R$ 900/mês, acompanhando alertas e desligando a homologação quando não estiver em uso;
2. otimizar a arquitetura para reduzir réplicas mínimas, observabilidade e tempo ligado, e então recalcular;
3. confirmar quais benefícios e créditos estudantis ainda estão disponíveis na assinatura, sem tratá-los como garantia permanente.

Em 10/11/2026, o responsável autorizou a cobrança e `paidResourcesApproved` passou a `true`. O alerta de R$ 100 não limita nem desliga o consumo; implantação continua condicionada às cotas e às demais barreiras do preflight.

## Relação com o `what-if`

O `what-if` é somente leitura e não cria recursos. O preflight agora distingue os propósitos:

- `-Purpose WhatIf` exige as decisões já confirmadas, mas não exige antecipadamente a autorização de cobrança, a conclusão de cotas ou o provedor de e-mail;
- `-Purpose Deployment` continua exigindo todas as oito aprovações humanas.

Isso permite revisar o plano antes de autorizar gastos sem enfraquecer a barreira de implantação. Em 10/11/2026, `Central US` foi aprovada por suportar os 19 tipos permitidos e o `what-if` `ProviderNoRbac` terminou com 62 criações previstas, uma implantação lógica e zero exclusões. A estimativa com `-Location centralus` ficou entre R$ 360,81 e R$ 785,51/mês, antes dos mesmos itens variáveis.

Atualização de 10/11/2026: a homologação foi implantada e está **cobrando**. O ACS Email entrou com custo por mensagem, desprezível no volume de testes. O perfil `carga`, usado só na janela do CQ09, dobra a vCPU dos seis serviços enquanto está ativo. Por decisão do responsável, o ambiente fica ligado até a apresentação. Para encerrar a cobrança, veja a seção 10 do [guia Bicep](GUIA-INFRAESTRUTURA-AZURE-BICEP.md).

O relatório usa `ResourceIdOnly` e devolve apenas `status`, `resourceId` e `changeType`. Esse formato conserva os dados necessários para detectar exclusões, sem materializar payloads completos nem segredos em um JSON local muito grande. O transporte ARM REST foi usado porque a conexão longa do Azure CLI era reiniciada nesta máquina; ambos consultam a mesma operação oficial de `what-if`.
