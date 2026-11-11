# Guia de administração da homologação Azure

Comandos prontos para administrar contas e serviços do NexFleet publicado na Azure.
Copie cada bloco **inteiro** no terminal e troque apenas o que estiver indicado como `TROQUE`.

> **Segurança**
> - Nenhum comando deste guia mostra ou grava senha em arquivo de texto.
> - Os comandos que **alteram** o banco pedem que você digite `CONFIRMAR` e **não têm como ser desfeitos**.
> - Rode sempre a consulta de conferência (somente leitura) antes de alterar ou apagar.
> - Nunca rode `UPDATE` ou `DELETE` sem `WHERE`: isso afetaria **todos** os usuários.

## Índice

| # | Tarefa | Altera dados? |
|---|---|---|
| 0 | [Preparar o terminal](#0-preparar-o-terminal) | Não |
| 1 | [Ver a senha do Administrador principal](#1-ver-a-senha-do-administrador-principal) | Não |
| 2 | [Verificar se um e-mail e uma senha estão corretos](#2-verificar-se-um-e-mail-e-uma-senha-estão-corretos) | Não |
| 3 | [Listar as contas cadastradas](#3-listar-as-contas-cadastradas) | Não |
| 4 | [Alterar a senha de uma conta](#4-alterar-a-senha-de-uma-conta) | **Sim** |
| 5 | [Desativar ou reativar uma conta](#5-desativar-ou-reativar-uma-conta) | **Sim** |
| 6 | [Alterar o perfil de uma conta](#6-alterar-o-perfil-de-uma-conta) | **Sim** |
| 7 | [Apagar uma conta definitivamente](#7-apagar-uma-conta-definitivamente) | **Sim** |
| 8 | [Acordar os serviços e verificar o ambiente](#8-acordar-os-serviços-e-verificar-o-ambiente) | Não |
| 9 | [Deixar os serviços sempre acordados ou dormindo](#9-deixar-os-serviços-sempre-acordados-ou-dormindo) | Configuração |
| 10 | [Problemas comuns](#10-problemas-comuns) | — |

**Pelo próprio sistema** (tela **Usuários**, só para Administrador) é possível cadastrar, editar o e-mail ou o perfil, desativar, reativar e **excluir** contas desativadas. Use este guia para o que a tela **não** faz, como ver ou trocar senha.

---

## 0. Preparar o terminal

Faça isto **sempre que abrir um terminal novo**: no VS Code, **Ctrl + '**, dentro da pasta do projeto.

```powershell
Set-ExecutionPolicy -Scope Process Bypass
az account show -o table      # se der erro, rode: az login
```

| Requisito | Para quais seções |
|---|---|
| Azure CLI com login feito (`az login`) | 3 a 7 e 9 |
| Docker Desktop aberto | 4 (gera o hash da senha) |
| Arquivo `infra/azure/preflight-profile.json` (só existe no seu PC) | 3 a 7 |
| Arquivo `.secrets/azure-homolog-admin.clixml` (só existe no seu PC) | 1 |

**Como funcionam as seções 3 a 7.** O banco da Azure é **privado**: não aceita conexão do seu PC nem do Portal. O script `scripts/Invoke-AzureDatabaseQuery.ps1` contorna isso assim:

1. Executa o seu SQL **dentro da rede da Azure**, por meio do job `job-nexfleet-db-verify`.
2. Usa o usuário do próprio banco, sem nenhum privilégio de administrador.
3. Devolve o resultado em **1 a 3 minutos**.

O script só lê dados. Alterações exigem a opção `-PermitirEscrita` e a confirmação `CONFIRMAR`.

---

## 1. Ver a senha do Administrador principal

A senha criada no deploy fica em `.secrets/azure-homolog-admin.clixml`, **criptografada pelo Windows (DPAPI)**. Só o seu usuário, neste PC, consegue abrir.

```powershell
$s = Import-Clixml .secrets\azure-homolog-admin.clixml
"E-mail: $($s.email)"
"Senha:  $([Net.NetworkCredential]::new('', $s.password).Password)"
```

Depois de copiar, limpe a tela com `cls`. **Não edite nem apague o `.clixml`.**

---

## 2. Verificar se um e-mail e uma senha estão corretos

O bloco testa o login exatamente como o site faz. A senha é digitada sem aparecer na tela.

```powershell
$api = 'https://apim-nexfleet-homolog-ukzjodf42myfe.azure-api.net'
$email = Read-Host 'E-mail'
$senha = Read-Host 'Senha' -AsSecureString
$body = @{ email = $email.Trim().ToLower(); senha = [Net.NetworkCredential]::new('', $senha).Password } | ConvertTo-Json
try {
    Invoke-RestMethod -Uri "$api/api/v1/auth/login" -Method Post -ContentType 'application/json' -Body $body -TimeoutSec 60 | Out-Null
    'CORRETO: login aceito.'
} catch {
    $code = 0
    if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
    switch ($code) {
        401     { 'INCORRETO: e-mail ou senha errados, ou conta desativada.' }
        400     { 'Dados inválidos: confira o formato do e-mail e o tamanho da senha.' }
        503     { 'Serviço dormindo ou indisponível. Rode a seção 8 e tente de novo.' }
        default { "Falha de conexão (HTTP $code): $($_.Exception.Message)" }
    }
}
$body = $null; $senha = $null
```

Para conferir a senha do **Administrador principal** guardada no `.clixml`, troque as duas linhas `Read-Host` por:

```powershell
$s = Import-Clixml .secrets\azure-homolog-admin.clixml; $email = $s.email; $senha = $s.password
```

---

## 3. Listar as contas cadastradas

**Todas as contas:**

```powershell
./scripts/Invoke-AzureDatabaseQuery.ps1 -Database identidade `
  -Sql "SELECT email, perfil, ativo FROM identidade.usuario ORDER BY perfil, email"
```

**Uma conta específica** (`TROQUE` o e-mail):

```powershell
$email = 'TROQUE@exemplo.com'
./scripts/Invoke-AzureDatabaseQuery.ps1 -Database identidade `
  -Sql "SELECT email, perfil, ativo FROM identidade.usuario WHERE email = lower('$email')"
```

A coluna `senha_hash` fica de fora de propósito. Ela guarda só o hash BCrypt, que não permite descobrir a senha.

---

## 4. Alterar a senha de uma conta

O sistema não tem a função "trocar senha" na tela. Este procedimento gera o **hash BCrypt** da nova senha no seu PC e grava esse hash no banco. A senha em si nunca sai do computador.

### Passo 1: digitar a nova senha e gerar o hash (precisa do Docker aberto)

```powershell
$email = 'TROQUE@exemplo.com'
$nova = Read-Host 'Nova senha (mínimo 12 caracteres)' -AsSecureString
$env:NX_SENHA = [Net.NetworkCredential]::new('', $nova).Password
if ($env:NX_SENHA.Length -lt 12) { $env:NX_SENHA = $null; throw 'A senha precisa ter pelo menos 12 caracteres.' }
$env:NX_PY = "import bcrypt,os;print(bcrypt.hashpw(os.environ['NX_SENHA'].encode(),bcrypt.gensalt(12)).decode())"
$hash = (docker run --rm -e NX_SENHA -e NX_PY python:3.13-slim sh -c 'pip install -q bcrypt==4.2.1 >/dev/null 2>&1 && echo $NX_PY | python -' | Select-Object -Last 1).Trim()
$env:NX_SENHA = $null; $env:NX_PY = $null
if ($hash -notmatch '^\$2[aby]\$12\$.{53}$') { throw 'Falha ao gerar o hash. O Docker está aberto?' } else { 'Hash gerado com sucesso.' }
```

### Passo 2: gravar o hash na Azure

```powershell
$sql = "UPDATE identidade.usuario SET senha_hash = '" + $hash + "' WHERE email = lower('" + $email + "') RETURNING email"
./scripts/Invoke-AzureDatabaseQuery.ps1 -Database identidade -PermitirEscrita -Sql $sql
```

Digite `CONFIRMAR` quando for pedido. O resultado esperado é o e-mail seguido de **`UPDATE 1`**. Se aparecer `UPDATE 0`, nenhuma conta tem esse e-mail.

> A SQL é montada com `+` de propósito. O hash contém vários `$`, que o PowerShell confundiria com variáveis se ficassem dentro de aspas duplas.

### Passo 3: só para o Administrador principal, atualizar o `.clixml`

Se você trocou a senha da conta guardada no `.clixml` (seção 1), atualize o arquivo. Os scripts de teste da homologação usam esse arquivo.

```powershell
[pscustomobject]@{ email = $email.ToLower(); password = $nova } |
    Export-Clixml .secrets\azure-homolog-admin.clixml -Force
```

### Passo 4: limpar e testar

```powershell
$nova = $null; $hash = $null; $sql = $null
```

Depois teste a nova senha com a **seção 2**.

---

## 5. Desativar ou reativar uma conta

Isso também pode ser feito pela tela **Usuários**. A conta desativada não consegue entrar, mas o cadastro e o histórico são preservados.

**Desativar:**

```powershell
$email = 'TROQUE@exemplo.com'
./scripts/Invoke-AzureDatabaseQuery.ps1 -Database identidade -PermitirEscrita `
  -Sql "UPDATE identidade.usuario SET ativo = false WHERE email = lower('$email') RETURNING email, ativo"
```

**Reativar:** é o mesmo comando, com `ativo = true`.

> Mantenha sempre **pelo menos um Administrador ativo**. O sistema não impede que você desative o último.

---

## 6. Alterar o perfil de uma conta

Isso também pode ser feito pela tela **Usuários**, botão **Editar**. Os perfis válidos são `ADMINISTRADOR` e `GESTOR_FROTA`.

```powershell
$email = 'TROQUE@exemplo.com'
$perfil = 'GESTOR_FROTA'      # ou ADMINISTRADOR
./scripts/Invoke-AzureDatabaseQuery.ps1 -Database identidade -PermitirEscrita `
  -Sql "UPDATE identidade.usuario SET perfil = '$perfil' WHERE email = lower('$email') RETURNING email, perfil"
```

A mudança vale a partir do **próximo login** da pessoa.

---

## 7. Apagar uma conta definitivamente

> **Desde a v0.30.0 isso pode ser feito pela tela:** em **Usuários**, desative a conta e clique em **Excluir**. O mesmo vale para veículos e motoristas inativos sem histórico (ADR 0038). Use os comandos abaixo só se a tela não estiver disponível.

> **Prefira desativar** (seção 5). Abastecimentos, manutenções e vínculos guardam **quem os registrou**. Ao apagar a conta, esses registros passam a apontar para alguém que não existe mais. Apague só contas que **nunca registraram nada**, como contas de teste.

### Passo 1: conferir o que será apagado (somente leitura)

```powershell
$email = 'TROQUE@exemplo.com'
./scripts/Invoke-AzureDatabaseQuery.ps1 -Database identidade `
  -Sql "SELECT email, perfil, ativo FROM identidade.usuario WHERE email = lower('$email')"
```

### Passo 2: apagar

```powershell
./scripts/Invoke-AzureDatabaseQuery.ps1 -Database identidade -PermitirEscrita `
  -Sql "DELETE FROM identidade.usuario WHERE email = lower('$email') RETURNING email"
```

Digite `CONFIRMAR`. O resultado esperado é o e-mail seguido de **`DELETE 1`**.

### Apagar as contas criadas pelo teste de homologação

O teste automático (`quality/azure/homolog.mjs`) cria uma conta `gestor.hml.<número>@example.com` a cada execução. Para apagar todas:

```powershell
# 1. Conferir: só devem aparecer contas gestor.hml...@example.com
./scripts/Invoke-AzureDatabaseQuery.ps1 -Database identidade `
  -Sql "SELECT email FROM identidade.usuario WHERE email LIKE 'gestor.hml.%@example.com' AND perfil = 'GESTOR_FROTA'"

# 2. Apagar
./scripts/Invoke-AzureDatabaseQuery.ps1 -Database identidade -PermitirEscrita `
  -Sql "DELETE FROM identidade.usuario WHERE email LIKE 'gestor.hml.%@example.com' AND perfil = 'GESTOR_FROTA' RETURNING email"
```

No `LIKE`, o `%` significa "qualquer texto". A condição `perfil = 'GESTOR_FROTA'` é uma trava extra: um Administrador nunca é apagado por esse comando.

---

## 8. Acordar os serviços e verificar o ambiente

No modo econômico, **Identidade**, **Frota** e **BFF** dormem depois de alguns minutos sem uso. O primeiro acesso leva de 30 a 60 s, e enquanto isso o login falha. O bloco abaixo chama o diagnóstico até os 4 serviços responderem:

```powershell
$api = 'https://apim-nexfleet-homolog-ukzjodf42myfe.azure-api.net'
for ($i = 1; $i -le 12; $i++) {
    try {
        $r = Invoke-RestMethod -Uri "$api/api/v1/ambiente" -TimeoutSec 60
        $estado = ($r.services | ForEach-Object { "$($_.name)=$($_.status)" }) -join '  '
    } catch {
        $r = $null; $estado = 'sem resposta'
    }
    "Tentativa ${i}: $estado"
    if ($r -and $r.status -eq 'UP') { 'Todos os serviços estão disponíveis.'; break }
    Start-Sleep -Seconds 10
}
```

O mesmo resultado aparece no site, no botão **Verificar ambiente**. Rode este bloco uns 5 minutos antes de uma apresentação.

---

## 9. Deixar os serviços sempre acordados ou dormindo

| Mínimo de réplicas | Comportamento | Custo |
|---|---|---|
| `0` (padrão para Identidade, Frota e BFF) | Dorme sem uso e acorda no primeiro acesso | Menor |
| `1` | Sempre ligado, login sempre rápido | Maior: cobra 24 h por dia |

**Sempre acordados** (por exemplo, no dia da apresentação):

```powershell
$az = 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'
foreach ($app in 'identidade','frota','bff') {
    & $az containerapp update -g rg-nexfleet-homolog -n "ca-$app-nexfleet-homolog" --min-replicas 1 -o none
}
```

**Voltar a dormir** (economia): é o mesmo comando, com `--min-replicas 0`.

**Conferir como está:**

```powershell
& $az containerapp list -g rg-nexfleet-homolog `
  --query "[].{app:name, minimo:properties.template.scale.minReplicas}" -o table
```

**Pelo Portal da Azure:**

1. Abra o grupo de recursos `rg-nexfleet-homolog`.
2. Abra o Container App do serviço, por exemplo `ca-identidade-nexfleet-homolog`.
3. Vá em **Aplicativo → Escala**, ajuste o campo **Mínimo de réplicas** e clique em **Salvar**.

> **Não** coloque `0` em Gateway, Operações ou Indicadores: Indicadores precisa ficar ligado para receber os eventos e atualizar o painel. Um novo `Deploy-AzureFoundation.ps1` volta tudo aos valores do Bicep.

---

## 10. Problemas comuns

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| Site: "Não foi possível acessar o serviço de identidade" | Identidade dormindo | Seção 8, depois tente de novo |
| Site: "E-mail, senha ou sessão inválidos" | Senha errada ou conta desativada | Seções 2 e 3 |
| Site: "Confira sua conexão" em `127.0.0.1` | Ambiente **local** desligado: o Docker não está rodando | Use o endereço da Azure ou `./scripts/Start-Local.ps1 -NoBuild` |
| `ConnectionResetError 10054` no terminal | Instabilidade de rede | Rode o comando de novo; os scripts já repetem sozinhos |
| `az: comando não encontrado` | Azure CLI fora do PATH | Use `& 'C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd'` |
| `AADSTS...` ou "Please run az login" | Sessão da Azure expirada | `az login` |
| "Falha ao gerar o hash" | Docker Desktop fechado | Abra o Docker e repita o Passo 1 da seção 4 |
| `cannot execute ... in a read-only transaction` | Faltou `-PermitirEscrita` | Inclua a opção no comando |
| `UPDATE 0` ou `DELETE 0` | Nenhuma conta com esse e-mail | Confira o e-mail na seção 3 |
| `Import-Clixml` dá erro | Outro usuário do Windows ou outro PC | Só funciona no usuário e no PC que fizeram o deploy |

Relacionados: [Guia de uso e operação](GUIA-USO-E-OPERACAO.md) · [Guia de infraestrutura Azure](GUIA-INFRAESTRUTURA-AZURE-BICEP.md)
