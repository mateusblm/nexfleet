# Aula 31 — descoberta Azure conectada sem criar recursos

## Objetivo

Separar fatos consultáveis de decisões humanas. A descoberta responde quais regiões e tipos estão disponíveis; ela não aprova custo, residência de dados, backup nem publicação.

## 1. Validar o script sem conta

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\Get-AzureReadiness.ps1 `
  -ValidateOnly
```

Esse modo valida o inventário de 16 tipos e as regiões candidatas sem procurar o Azure CLI.

## 2. Autenticar

```powershell
az login
az account show --output table
```

Não copie tokens, senhas ou chaves para o projeto. O script usa a sessão local do Azure CLI.

## 3. Executar a descoberta

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\Get-AzureReadiness.ps1
```

As candidatas padrão são:

- `brazilsouth`: backend e dados;
- `brazilsoutheast`: comparação regional;
- `eastus2`: metadados do Static Web Apps.

Para comparar outras regiões:

```powershell
.\scripts\Get-AzureReadiness.ps1 `
  -Locations brazilsouth,eastus2,westeurope
```

## 4. Interpretar o resultado

`Provider=Registered` informa que o namespace está habilitado na assinatura. `Type=OK` informa que o tipo foi encontrado. As colunas de região mostram a disponibilidade anunciada pelo provedor.

O relatório fica em `infra/azure/preflight-report-*.json`. Ele é ignorado pelo Git porque contém o UUID da assinatura, mas não contém credenciais.

Um provedor `NotRegistered` não é registrado pelo script. A descoberta termina normalmente para que a equipe possa revisar a pendência.

## 5. Resultado observado

Na execução de 08/11/2026:

- a assinatura estava `Enabled`;
- os 16 tipos foram encontrados;
- `Brazil South` suportou 15 tipos;
- Static Web Apps exigiu uma região separada;
- cinco provedores necessários estavam `NotRegistered`;
- nenhum recurso ou provedor foi alterado.

## 6. Próxima barreira

Preencha o perfil v3 somente depois de aprovar orçamento, regiões, cotas, backup e notificação. O preflight completo e o `what-if` permanecem etapas posteriores e não autorizam implantação.
