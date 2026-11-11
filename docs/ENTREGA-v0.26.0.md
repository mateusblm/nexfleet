# Entrega v0.26.0 — infraestrutura Bicep bloqueada por padrão

Data: 08/11/2026.

## Entregue

- Bicep de assinatura e módulo de plataforma, compilados com Bicep 0.49.2.
- Grupo, orçamento, monitoramento, ACR, Key Vault, Storage, Service Bus, PostgreSQL 18, Container Apps Environment, Static Web App, APIM e Function Flex modelados.
- Identidade gerenciada e RBAC da Function para Storage/Application Insights.
- Inventário ampliado de 12 para 16 tipos de recurso.
- Perfil Azure v2 compatível com assinatura paga ou estudantil e moeda de cobrança configurável.
- `publicationApproved=false` por padrão.
- Plano de exemplo sem autorização, conta ou segredo.
- Validação offline integrada à suíte e à CI.
- Script conectado que executa somente preflight + `what-if` e reprova exclusões.

## Comprovado

- lint Bicep: aprovado sem avisos;
- build Bicep: aprovado;
- 15 tipos presentes nos templates e 1 pendente de forma explícita;
- exemplo de preflight: 16 tipos e zero aprovações presumidas;
- exemplo de plano: bloqueia antes do Azure CLI;
- nenhum recurso Azure criado, alterado ou excluído.

## Pendente

- conectar a conta para preflight e `what-if` reais;
- confirmar região, moeda, cotas, SKUs e estimativa;
- migrar mensageria cloud de RabbitMQ para Service Bus;
- adicionar rede privada e usuários separados dos cinco databases;
- modelar os seis Container Apps com imagens reais;
- configurar provedor externo de notificação;
- implantar HTTPS e repetir CQ09/CQ10.

A Sprint 4 permanece em andamento. Consulte o [guia Bicep](GUIA-INFRAESTRUTURA-AZURE-BICEP.md) antes de autenticar uma conta.
