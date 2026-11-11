# ADR 0030 — pré-publicação Azure somente de leitura

## Status

Aceita em 08/11/2026.

## Contexto

A Sprint 4 exige publicação Azure, mas a equipe ainda precisa confirmar assinatura, região, cotas, orçamento, backup e provedor de notificações. Criar recursos antes dessas decisões pode gerar cobrança ou escolher serviços indisponíveis na região.

O Azure CLI não está instalado na máquina verificada, e nenhum identificador de assinatura foi fornecido ao repositório.

## Decisão

Introduzir uma barreira de pré-publicação em `Test-AzurePreflight.ps1`:

- o perfil real permanece fora do Git;
- o modelo exige orçamento, alertas e oito aprovações humanas;
- a CI valida apenas o modelo sem dados reais;
- a execução conectada usa `az account show`, `az account list-locations` e `az provider show`;
- o script nunca registra provedores nem cria, altera ou remove recursos.

O inventário inicial contém os 12 tipos de recurso da arquitetura-alvo. Um preflight aprovado não substitui o `what-if` da futura infraestrutura como código nem concede autorização para implantar.

## Alternativas consideradas

### Criar diretamente um grupo de recursos de teste

Descartada porque já seria uma mutação externa e não resolveria orçamento, cotas ou serviços regionais.

### Registrar automaticamente todos os provedores

Descartada para preservar privilégio mínimo e evitar alterações não aprovadas na assinatura.

### Guardar a assinatura em arquivo versionado

Descartada. Mesmo não sendo senha, o identificador e os e-mails pertencem ao perfil local do ambiente.

## Consequências

- A publicação falha cedo e explica as decisões pendentes.
- Windows e macOS podem executar o mesmo pré-check por PowerShell.
- A disponibilidade real só poderá ser comprovada depois de instalar o Azure CLI, autenticar e preencher o perfil.
- Preços e saldo não são inferidos pelo script; devem ser confirmados no portal e no orçamento aprovado.
