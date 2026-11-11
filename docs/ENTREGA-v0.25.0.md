# Entrega v0.25.0 — preflight Azure sem criação de recursos

## Resultado

A Sprint 4 ganhou uma barreira executável antes da publicação. Assinatura, região, orçamento, alertas, cotas, backup, notificações e disponibilidade dos serviços precisam ser confirmados antes de qualquer infraestrutura como código.

## Entregas

- Schema e exemplo do perfil de homologação, sem dados reais.
- Inventário de 12 tipos de recurso Azure exigidos pela arquitetura-alvo.
- `Test-AzurePreflight.ps1` com modo offline de CI e modo conectado somente de leitura.
- Bloqueio explícito para orçamento zero, campos substitutos ou qualquer uma das oito aprovações pendentes.
- Integração do modelo em `Test-Project.ps1` e no workflow backend.
- Guia de pré-publicação, ADR 0030 e Aula 29.

## Verificação

- O modelo vazio passou no modo `-TemplateOnly`.
- A execução normal com o exemplo foi reprovada antes do Azure CLI e listou todas as decisões pendentes.
- O Azure CLI não está instalado nesta máquina; portanto, nenhuma assinatura ou região foi consultada.
- Nenhum comando de criação, alteração, registro de provedor ou exclusão foi executado.

## O que permanece aberto

É necessário instalar o Azure CLI, autenticar, preencher o perfil real e obter as aprovações. Depois disso ainda faltam infraestrutura como código com revisão `what-if`, implantação HTTPS, decisão do provedor de notificações e repetição de CQ09/CQ10 na homologação.
