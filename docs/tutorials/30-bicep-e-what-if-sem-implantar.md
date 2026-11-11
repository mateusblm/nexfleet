# Aula 30 — Bicep e what-if sem implantar

## Objetivo

Converter a arquitetura Azure em código verificável sem usar uma assinatura e sem criar recursos.

## 1. Bicep não executa sozinho

Um arquivo `.bicep` é uma descrição declarativa. `bicep build` transforma essa descrição em ARM JSON localmente. A compilação não autentica no Azure.

No NexFleet, `main.bicep` atua na assinatura porque precisa descrever grupo de recursos e orçamento. O módulo `platform.bicep` atua dentro do grupo e descreve os serviços gerenciados.

## 2. Nomes e segredos

Nomes globais recebem um token estável derivado da assinatura, grupo e região. O output informa somente nomes; nunca senha, chave ou connection string.

A senha do PostgreSQL é um parâmetro `@secure()`. Ela não aparece no exemplo. Quando o `what-if` conectado for autorizado, o script a lê de uma variável de sessão, cria um JSON temporário e o remove ao final.

## 3. Travas independentes

Há três barreiras:

1. `preflight-profile.json`: assinatura, região, orçamento e aprovações;
2. `deployment-plan.json`: decisão Service Bus e permissão somente para `what-if`;
3. `publicationApproved=false`: padrão do próprio Bicep.

O exemplo não abre nenhuma dessas barreiras. O repositório também não contém um script que chame `az deployment ... create`.

## 4. Compilação local

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\Test-AzureInfrastructure.ps1
```

O teste compara o inventário com as declarações Bicep, confirma que apenas Container Apps está pendente, executa o linter e compila um ARM JSON temporário.

## 5. Diferença entre build e what-if

- **build:** valida linguagem e tipos localmente;
- **what-if:** pede ao Azure Resource Manager que preveja criações/modificações na assinatura real;
- **deploy:** altera a assinatura.

A v0.26.0 implementa os dois primeiros caminhos, mas deixa o segundo bloqueado até a conta ser conectada. O terceiro não foi implementado.

## 6. Por que Service Bus aparece no plano

A Function atual é acionada por RabbitMQ localmente. Em Flex Consumption, esse binding não é suportado plenamente. Service Bus possui gatilho nativo para Functions e emulador Docker para desenvolvimento local.

Isso ainda é uma decisão de migração, não uma alegação de que o código já usa Service Bus. Operações, Indicadores e Function precisarão de adaptadores e testes antes dos Container Apps.

## 7. Resultado desta aula

O projeto possui uma infraestrutura auditável e compilável, mas não cria recursos e não finge que os workloads estão prontos. O próximo passo técnico é migrar a mensageria cloud e, paralelamente, conectar a conta apenas para o preflight e `what-if`.
