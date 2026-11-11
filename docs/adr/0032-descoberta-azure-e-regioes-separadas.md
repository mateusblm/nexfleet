# ADR 0032 — descoberta Azure e regiões separadas

Data: 08/11/2026  
Estado: aceita

## Contexto

O preflight da v0.26.0 exigia oito aprovações antes de consultar a conta. Algumas decisões, especialmente disponibilidade regional e registro de provedores, dependem justamente dessas consultas. Além disso, a primeira execução real mostrou que `Microsoft.Web/staticSites` não está disponível em `Brazil South`, embora os outros 15 tipos planejados estejam.

O Azure CLI também havia sido instalado depois da abertura do processo do editor, deixando o comando fora do `PATH` daquele processo. A combinação `az account list-locations --subscription` não é aceita pela versão instalada.

## Decisão

1. Separar descoberta de aprovação com `Get-AzureReadiness.ps1`.
2. Permitir que a descoberta leia assinatura, regiões, provedores e tipos sem exigir perfil, orçamento ou aprovações fictícias.
3. Nunca registrar provedores nem criar, alterar ou excluir recursos durante a descoberta.
4. Gravar um relatório local ignorado pelo Git e ocultar UUIDs nas mensagens de erro.
5. Resolver o Azure CLI pelo `PATH` ou pelos caminhos oficiais conhecidos no Windows.
6. Consultar todos os provedores em uma única leitura e repetir somente falhas transitórias.
7. Evoluir o perfil para schema v3, separando `location` de `staticWebLocation`.
8. Manter `Brazil South` como candidata principal e `East US 2` apenas como candidata explícita para os metadados do Static Web Apps.

## Consequências

- A equipe consegue descobrir bloqueios antes de afirmar que orçamento, cota e região estão aprovados.
- O Bicep deixa de tentar criar Static Web Apps em uma região incompatível.
- A existência de uma região compatível não equivale a aprovação de residência de dados.
- Estados `NotRegistered` aparecem no relatório, mas qualquer registro exige uma ação posterior e autorizada.
- O `what-if` continua bloqueado até o perfil real e as oito aprovações estarem completos.

## Evidência

A descoberta conectada verificou 16 tipos na assinatura `Azure for Students`. `Brazil South` atende 15; Static Web Apps oferece `Central US`, `East Asia`, `East US 2`, `West Europe` e `West US 2`. Cinco provedores necessários estavam `NotRegistered`. O relatório confirmou zero recursos criados, zero provedores registrados e nenhuma troca de assinatura.
