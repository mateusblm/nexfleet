# Entrega v0.27.0 — descoberta Azure conectada

Data: 08/11/2026.

## Resultado

A conta Azure foi autenticada e a arquitetura foi consultada sem criar recursos. A nova etapa de descoberta remove a dependência circular entre consulta técnica e aprovações humanas.

## Implementado

- `Get-AzureReadiness.ps1` com modo offline e conectado;
- resolução compartilhada do Azure CLI fora do `PATH`;
- repetição limitada de falhas transitórias e ocultação de UUIDs em erros;
- relatório local ignorado pelo Git;
- perfil Azure schema v3 com `staticWebLocation`;
- Bicep com região separada para Static Web Apps;
- preflight compatível com a CLI instalada e consulta consolidada de provedores;
- validações offline na suíte local e na CI;
- ADR 0032 e Aula 31.

## Evidência conectada

| Item | Resultado |
|---|---|
| Assinatura | `Azure for Students`, estado `Enabled` |
| Tipos encontrados | 16/16 |
| Suporte em `Brazil South` | 15/16 |
| Static Web Apps | região separada necessária; `East US 2` é candidata |
| Tipos prontos nas regiões candidatas | 11/16 |
| Provedores pendentes | API Management, Container Registry, PostgreSQL, Key Vault e Managed Identity |
| Recursos criados/alterados | 0 |
| Provedores registrados | 0 |

## Verificação local

- perfil v3 e descoberta offline aprovados;
- Bicep 0.49.2 aprovado em lint e build;
- 4 testes de qualidade/contratos aprovados;
- 172 testes dos seis serviços Java aprovados;
- 8 testes e pacote da Azure Function aprovados;
- 47 testes frontend e quatro builds Vite aprovados.

## Ainda não autorizado

- registro dos cinco provedores;
- criação do perfil real com aprovações verdadeiras;
- execução do `what-if`;
- criação de grupo, orçamento ou recursos;
- publicação de imagens/código;
- qualquer consumo intencional do crédito Azure.

## Próximo passo

Revisar orçamento, moeda, regiões e as oito aprovações. Somente depois disso decidir se os cinco provedores podem ser registrados e executar o preflight completo.
