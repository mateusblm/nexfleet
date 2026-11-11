# Aula 29 — conferir a Azure sem criar recursos

## 1. Por que existe uma barreira

Cloud não começa pelo botão “Criar”. Primeiro confirmamos conta, região, moeda, custo e responsabilidade. Assinaturas pagas geram cobrança e assinaturas estudantis possuem crédito limitado; nem todo serviço ou SKU está disponível em todas as regiões.

## 2. Dois modos do script

Na suíte local e na CI usamos:

```powershell
./scripts/Test-AzurePreflight.ps1 -TemplateOnly
```

Esse modo verifica o contrato, os 12 tipos de recurso e garante que o exemplo não contenha assinatura real nem aprovações antecipadas.

Depois das decisões, a equipe cria `infra/azure/preflight-profile.json` e executa o modo conectado:

```powershell
./scripts/Test-AzurePreflight.ps1
```

## 3. Ordem das proteções

O script trabalha nesta ordem:

1. valida JSON e campos obrigatórios;
2. exige UUID real, região, orçamento e e-mails;
3. exige as oito aprovações humanas;
4. procura o Azure CLI;
5. consulta assinatura e regiões;
6. consulta provedores e tipos de recurso;
7. produz o resultado sem alterar nada.

Isso significa que um perfil incompleto falha mesmo em uma máquina sem Azure CLI.

## 4. Por que não usamos `az account set`

Cada consulta recebe `--subscription`. Assim, o script não muda a assinatura padrão usada por outros trabalhos no terminal.

## 5. Por que `Registering` é aceito

A documentação do Azure Resource Manager informa que recursos podem prosseguir enquanto o provedor está em `Registering`. Estados como `NotRegistered` permanecem bloqueados. Mesmo assim, o script não inicia o registro.

## 6. O que o resultado não prova

O preflight não mede desempenho, restaura backup, configura e-mail, cria orçamento ou calcula preço. Ele confirma que a equipe declarou essas decisões e que a assinatura informa suporte para os componentes na região.

CQ09 e CQ10 somente poderão ser repetidos depois da homologação existir. A criação futura deverá usar infraestrutura como código e revisão `what-if` antes do deploy.
