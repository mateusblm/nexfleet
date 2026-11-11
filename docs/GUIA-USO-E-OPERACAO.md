# NexFleet — guia de uso e operação

Este guia explica, em linguagem direta:

1. o que é o NexFleet e como ele funciona por dentro;
2. como usar o sistema na nuvem e no computador local;
3. como executar o projeto;
4. como consultar os bancos de dados, localmente e na Azure;
5. o que são o RabbitMQ e o Prometheus e como usá-los.

Os detalhes de cada assunto estão nos guias específicos, citados ao longo do texto.

---

## 1. O que é o NexFleet

O NexFleet é uma plataforma web para gerenciar a frota de uma empresa. Ela substitui planilhas e mensagens soltas por um lugar único onde ficam:

- **veículos** (placa, marca, modelo, ano, quilometragem e situação);
- **motoristas** (CPF, CNH, categoria e validade);
- **vínculos**, que registram qual motorista usa qual veículo e em que período;
- **abastecimentos** e **manutenções**, com valores e quilometragem;
- um **painel** com gastos, situação da frota e próximas manutenções.

Há dois perfis de acesso:

| Perfil | O que pode fazer |
|---|---|
| **Administrador** | Tudo o que o Gestor faz, mais cadastrar e gerenciar usuários. |
| **Gestor de Frota** | Cadastrar e consultar veículos, motoristas, vínculos, abastecimentos e manutenções, e acompanhar o painel. |

O motorista é apenas um cadastro: ele não acessa o sistema nesta versão.

---

## 2. Como o sistema funciona por dentro

### 2.1 As peças

```text
Navegador
   │  HTTPS
   ▼
Shell web + 3 microfrontends (Frota, Operações, Painel)
   │  HTTPS
   ▼
API Gateway  ──►  BFF  ──►  Identidade │ Frota │ Operações │ Indicadores
                                │          │         │            │
                             PostgreSQL PostgreSQL PostgreSQL  PostgreSQL
                                                   │
                                     outbox → broker de eventos
                                                   │
                                   ┌───────────────┴──────────────┐
                                   ▼                              ▼
                        Indicadores (painel)        Função serverless (e-mail)
```

| Peça | Papel | Analogia |
|---|---|---|
| **Shell e microfrontends** | Telas. O shell monta a página e carrega três "pedaços" independentes: Frota, Operações e Painel. | Um shopping (shell) com lojas independentes (microfrontends). |
| **API Gateway** | Porta única de entrada das APIs. | A portaria do prédio. |
| **BFF** (*Backend for Frontend*) | Monta as respostas no formato que as telas precisam. Não contém regra de negócio. | O recepcionista que chama os departamentos certos. |
| **Identidade** | Usuários, senhas (BCrypt) e login. Emite o token JWT. | O RH que emite crachás. |
| **Frota** | Veículos, motoristas e vínculos. | O departamento de cadastro. |
| **Operações** | Abastecimentos, manutenções e hodômetro. | O departamento operacional. |
| **Indicadores** | Calcula o painel a partir dos eventos. | O departamento de relatórios. |
| **Broker de eventos** | Entrega os avisos "algo aconteceu" para quem tem interesse. É o RabbitMQ no computador local e o Service Bus na Azure. | Os Correios internos. |
| **Função serverless** | Ao receber um evento de abastecimento, envia o aviso por e-mail. | O mensageiro que só trabalha quando há carta. |

**Cada serviço tem o próprio banco.** Frota não lê o banco de Operações e vice-versa. Quando um serviço precisa de um dado de outro, ele pergunta pela API ou recebe um evento. Isso permite publicar e evoluir cada parte separadamente.

### 2.2 A lógica de um abastecimento, passo a passo

Este é o fluxo mais importante do sistema e mostra todos os estilos de arquitetura juntos.

1. O gestor preenche o formulário na tela **Operações → Abastecimentos**.
2. A requisição passa por Gateway → BFF → serviço Operações, sempre com o token JWT. Sem token, a resposta é **401**. Com um perfil sem permissão, a resposta é **403**.
3. Operações **pergunta ao serviço Frota** se existe, na data informada, um vínculo válido entre esse veículo e esse motorista: veículo e motorista ativos e CNH dentro da validade.
4. Operações confere as regras:
   - litros, valor e quilometragem precisam ser maiores que zero;
   - a data não pode estar no futuro;
   - a quilometragem não pode ser menor que a atual do veículo. O hodômetro nunca volta; se voltar, a resposta é **422**.
5. Em **uma única transação** do banco de Operações, o serviço grava o abastecimento, o novo hodômetro e um registro na tabela **outbox** (a "caixa de saída" do evento). Se qualquer parte falhar, nada é gravado (*rollback*).
6. A tela recebe **201 Criado**. Nesse momento o abastecimento já está garantido.
7. Logo depois, o publicador lê a outbox e envia o evento `AbastecimentoRegistrado.v1` ao broker.
8. Dois consumidores recebem o evento, cada um na sua fila:
   - **Indicadores** atualiza os totais do painel;
   - a **Função** grava a notificação e envia o e-mail.
9. Cada consumidor guarda o `eventId` que já processou. Se o mesmo evento chegar duas vezes, ele é ignorado (**idempotência**). Uma mensagem que falha 3 vezes vai para a **DLQ** (fila de mensagens com erro), sem travar as demais.

Por isso, o painel pode levar alguns segundos para mostrar um abastecimento novo. Essa espera é a **consistência eventual**: o registro é imediato, e os relatórios são atualizados logo depois.

### 2.3 Principais regras de negócio

| Regra | Onde é garantida |
|---|---|
| Placa única; CPF e CNH únicos | Frota, com índice único no banco |
| Veículo inativo não recebe abastecimento, manutenção nem vínculo | Frota e Operações |
| Um veículo tem no máximo um vínculo ativo por vez | Frota |
| O motorista precisa estar ativo e com CNH válida | Frota |
| A quilometragem nunca diminui | Operações, na mesma transação |
| A próxima manutenção precisa ser posterior à atual | Operações |
| Os históricos nunca são apagados (inativação lógica) | Todos os serviços |
| Veículo em manutenção não conta como disponível no painel | Indicadores |

---

## 3. Usar o sistema

### 3.1 Na nuvem (homologação Azure)

| Item | Valor |
|---|---|
| Endereço do sistema | https://white-mushroom-0cadda010.3.azurestaticapps.net |
| API (uso técnico) | https://apim-nexfleet-homolog-ukzjodf42myfe.azure-api.net |
| Login do Administrador | o e-mail informado na publicação |
| Senha | gerada uma única vez e guardada criptografada no computador de quem publicou, em `.secrets/azure-homolog-admin.clixml` |

Para ler a senha nesse computador, no **PowerShell 7**:

```powershell
(Import-Clixml .secrets\azure-homolog-admin.clixml).password | ConvertFrom-SecureString -AsPlainText
```

No Windows PowerShell 5.1:

```powershell
$s = (Import-Clixml .secrets\azure-homolog-admin.clixml).password
[Net.NetworkCredential]::new('', $s).Password
```

O arquivo só abre no mesmo usuário do Windows que o criou. A proteção é do próprio Windows (DPAPI).

**Dá para acessar de outra máquina?** Sim. O endereço é público e usa HTTPS. Funciona em qualquer computador ou celular com internet, sem instalar nada. Basta o login e a senha. Para outras pessoas, o recomendado é que o Administrador crie contas próprias em **Usuários** (por exemplo, Gestores), em vez de compartilhar a senha do Administrador.

O que **não** é público, por segurança:

- o banco de dados (veja a seção 5.2);
- os serviços internos. Só o API Management fica exposto.

**Cuidados:**

- **Primeiro acesso lento:** Identidade, Frota e BFF desligam quando ficam sem uso, para economizar. O primeiro login depois de um tempo pode levar de 20 a 30 segundos, ou falhar uma vez. Basta tentar de novo. Antes de uma apresentação, abra o site alguns minutos antes.
- **Sessão:** o token fica só na memória do navegador. Recarregar a página (F5) pede login de novo. Isso é intencional, por segurança.
- **Custo:** o ambiente cobra por hora enquanto existir.

### 3.2 Roteiro de uso: do cadastro ao painel

Siga esta ordem, porque cada passo depende do anterior:

1. **Entrar** com e-mail e senha.
2. **Usuários** (somente Administrador): cadastre um Gestor de Frota com e-mail, senha de 12 caracteres ou mais e perfil. Também é possível desativar contas.
3. **Frota → Veículos:** cadastre um veículo com placa, marca, modelo, ano, tipo, quilometragem inicial, status e data de aquisição.
4. **Frota → Motoristas:** cadastre um motorista com nome, CPF de 11 dígitos, CNH de 11 dígitos, categoria, validade da CNH (precisa estar no futuro para poder ser vinculado), telefone e status Ativo.
5. **Frota → Vínculos:** vincule o motorista ao veículo. Sem vínculo, o abastecimento é recusado.
6. **Operações → Abastecimentos:** registre o abastecimento com veículo, motorista, data, combustível, litros, valor e quilometragem. Teste o erro de propósito: informe uma quilometragem menor que a anterior. O sistema recusa e mantém os outros campos preenchidos.
7. **Operações → Manutenções:** registre uma manutenção com tipo, data, quilometragem, descrição, oficina, valor e, se houver, a data da próxima.
8. **Visão geral (painel):** veja gastos, situação da frota e próximas manutenções. O abastecimento aparece em alguns segundos.
9. Na nuvem, o abastecimento também gera um **e-mail** para o destinatário configurado. O remetente é `DoNotReply@…azurecomm.net`; confira a caixa de spam.

Erros comuns e seus significados:

| Mensagem/código | Significado |
|---|---|
| 401 | Sem login ou sessão expirada. Entre de novo. |
| 403 | O perfil não tem permissão para essa ação. |
| 404 | O registro não existe. |
| 409 | Placa, CPF, CNH ou e-mail já cadastrado. |
| 422 | Regra de negócio violada (km menor, sem vínculo, CNH vencida etc.). |
| 503/504 | Serviço acordando (na nuvem) ou fora do ar (local). Tente de novo. |

---

## 4. Executar o projeto no computador

O passo a passo completo, com solução de problemas, está no [guia de execução local](GUIA-EXECUCAO-LOCAL.md) (Windows) e no [guia para macOS](GUIA-EXECUCAO-MACOS.md). O resumo:

**Pré-requisitos:** Docker Desktop iniciado e PowerShell. Node.js e Java não precisam ser instalados: o projeto baixa cópias portáteis.

```powershell
# Na pasta do projeto (sem acentos no caminho, de preferência)
Set-ExecutionPolicy -Scope Process Bypass

# 1. Primeira vez: baixar dependências (Node, JDK, npm, Maven, imagens)
./scripts/Install-Dependencies.ps1

# 2. Primeira vez: criar .env.sprint0 e a chave JWT
./scripts/Initialize-Local.ps1
#    Abra .env.sprint0 e troque LOCAL_USER_PASSWORD por uma senha forte.

# 3. Subir backend, bancos, RabbitMQ, Function e Prometheus
./scripts/Start-Local.ps1 -ProvisionUser   # na primeira vez (cria o usuário)
./scripts/Start-Local.ps1 -NoBuild         # nas vezes seguintes
```

Depois, abra **quatro terminais**. Em cada um, rode `. .\scripts\Use-Local-Toolchain.ps1` e então:

| Terminal | Comando | Porta |
|---|---|---:|
| Shell | `cd frontend; npm.cmd run dev` | 5173 |
| Frota | `cd microfrontends/frota; npm.cmd run dev` | 5174 |
| Operações | `cd microfrontends/operacoes; npm.cmd run dev` | 5175 |
| Painel | `cd microfrontends/painel; npm.cmd run dev` | 5176 |

Acesse **http://127.0.0.1:5173** e entre com `LOCAL_USER_EMAIL` e `LOCAL_USER_PASSWORD` do `.env.sprint0`.

| Endereço local | O que é |
|---|---|
| http://127.0.0.1:5173 | Sistema (shell) |
| http://127.0.0.1:8080 | API Gateway |
| http://127.0.0.1:15672 | Painel do RabbitMQ |
| http://127.0.0.1:9090 | Prometheus |

Para parar, use `Ctrl+C` nos quatro terminais e depois `./scripts/Stop-Local.ps1`. Os dados são preservados. **Nunca** use `docker compose down -v`: esse comando apaga todos os dados locais.

Para rodar todos os testes: `./scripts/Test-Project.ps1`.

O ambiente local funciona só no seu computador: todas as portas ficam em `127.0.0.1`. Para outra pessoa usar, ela precisa instalar o projeto na máquina dela, ou usar a versão na nuvem.

---

## 5. Acessar os bancos de dados

Há **cinco bancos PostgreSQL**, um por serviço: `identidade`, `frota`, `operacoes`, `indicadores` e `notificacoes`. Cada um tem um schema com o mesmo nome.

| Banco | Tabelas principais |
|---|---|
| identidade | `usuario` |
| frota | `veiculo`, `motorista`, `veiculo_motorista` (vínculos) |
| operacoes | `abastecimento`, `manutencao`, `hodometro`, `outbox_evento` |
| indicadores | `abastecimento_projecao`, `manutencao_projecao` (projeções do painel, com o `eventId` que garante a idempotência) |
| notificacoes | `email_capturado` (notificações e status de envio) |

**Regra de ouro:** use o banco para **consultar**. Cadastros e alterações devem ser feitos pelo sistema. Uma alteração direta pula validações, autorização, outbox e eventos, e deixa os dados inconsistentes.

### 5.1 Banco local

Pelo terminal, com o backend em execução:

```powershell
docker exec -it nexfleet-sprint0-frota-db-1 psql -U frota -d frota
```

Dentro do `psql`:

```sql
SET search_path TO frota;
\dt                                   -- lista as tabelas
SELECT placa, marca, status, quilometragem FROM veiculo ORDER BY criado_em DESC;
\q                                    -- sai
```

Os outros bancos seguem o mesmo padrão, trocando `frota` pelo nome do banco (`identidade`, `operacoes`, `indicadores` ou `notificacoes`).

Pelo pgAdmin ou DBeaver: suba também o arquivo `compose.db-access.yaml` e conecte em `127.0.0.1`, nas portas 15432 a 15436, com as senhas do `.env.sprint0`. A tabela completa está no [guia de execução local, seção 9.3](GUIA-EXECUCAO-LOCAL.md).

### 5.2 Banco na Azure

O PostgreSQL da nuvem **não tem acesso público**: ele só aceita conexões de dentro da rede privada da Azure. Por isso o pgAdmin do seu computador não conecta, e isso é intencional, porque é o que protege os dados.

Para consultar, use o script abaixo. Ele executa a SQL **dentro da rede privada**, com o usuário do próprio banco (nunca o administrador), e em **modo somente leitura**: `INSERT`, `UPDATE`, `DELETE` e alterações de estrutura são recusados pelo PostgreSQL.

```powershell
./scripts/Invoke-AzureDatabaseQuery.ps1 -Database frota `
  -Sql "SELECT placa, marca, status, quilometragem FROM frota.veiculo ORDER BY criado_em"

./scripts/Invoke-AzureDatabaseQuery.ps1 -Database operacoes `
  -Sql "SELECT realizado_em, combustivel, litros, valor_total, quilometragem FROM operacoes.abastecimento ORDER BY realizado_em DESC LIMIT 10"

./scripts/Invoke-AzureDatabaseQuery.ps1 -Database notificacoes `
  -Sql "SELECT solicitado_em, status, provedor FROM notificacoes.email_capturado ORDER BY solicitado_em DESC LIMIT 10"
```

O resultado leva de 1 a 3 minutos para chegar, porque a consulta roda como um job na nuvem e a saída é lida no Log Analytics. O script exige o Azure CLI com login na assinatura (`az login`) e o perfil `infra/azure/preflight-profile.json`.

---

## 6. RabbitMQ e Prometheus

Os dois são usados no **ambiente local**. Na Azure, os papéis equivalentes são o **Service Bus** e o **Azure Monitor / Application Insights / Log Analytics**.

### 6.1 RabbitMQ: o broker de eventos

**O que é:** um servidor de mensagens. Em vez de Operações chamar diretamente o Indicadores e a Função, ele publica um evento ("abastecimento registrado") e o RabbitMQ entrega uma cópia em cada fila interessada.

**Por que usar:**

- se o Indicadores estiver fora do ar, o abastecimento continua sendo registrado e a mensagem espera na fila;
- quem publica não precisa conhecer quem consome;
- falhas repetidas não se perdem: vão para a DLQ, onde podem ser analisadas.

**Os elementos no NexFleet:**

| Elemento | Nome | Função |
|---|---|---|
| Exchange (distribuidor) | `nexfleet.eventos` (tipo *topic*) | Recebe os eventos de Operações. |
| Chave do abastecimento | `operacoes.abastecimento.registrado.v1` | Endereço do evento de abastecimento. |
| Chave da manutenção | `operacoes.manutencao.registrada.v1` | Endereço do evento de manutenção. |
| Fila da Função | `nexfleet.notificacoes.abastecimentos.v1` | Abastecimentos para envio de aviso, com no máximo 3 tentativas. |
| Filas do Indicadores | `nexfleet.indicadores.projecao-abastecimentos.v1.com-dlq` e `...projecao-manutencoes.v1.com-dlq` | Eventos que atualizam o painel. |
| Exchange de erro | `nexfleet.eventos.dlx` | Recebe o que falhou 3 vezes. |
| DLQs | filas terminadas em `.dlq` | Mensagens com erro, guardadas para análise. |

**Como usar:**

1. Com o ambiente local no ar, abra **http://127.0.0.1:15672**.
2. Entre com `RABBITMQ_USER` e `RABBITMQ_PASSWORD` do `.env.sprint0`.
3. Aba **Exchanges → nexfleet.eventos → Bindings:** mostra para quais filas cada tipo de evento vai.
4. Aba **Queues:** mostra cada fila com as colunas *Ready* (aguardando), *Unacked* (em processamento) e as taxas por segundo. O normal é *Ready* em 0: tudo consumido.
5. Registre um abastecimento no sistema e observe as taxas das filas subirem por um instante.
6. Para ver uma mensagem com erro, abra uma fila `.dlq` e clique em **Get messages**. É uma leitura para análise; escolha o modo que **devolve** a mensagem para não perdê-la.
7. `./scripts/Test-Sprint2Eda.ps1` e `./scripts/Test-Sprint3Serverless.ps1` provam automaticamente a entrega, a duplicata ignorada e a DLQ.

**Na Azure:** o Service Bus faz o mesmo papel, com um tópico `nexfleet-eventos-v1` e duas assinaturas, `indicadores-v1` e `notificacoes-abastecimentos-v1`. Cada assinatura tem um filtro por tipo de evento, no máximo 3 entregas e uma DLQ. Para ver os contadores: portal Azure → Service Bus → tópico → assinaturas.

### 6.2 Prometheus: as métricas

**O que é:** um coletor de métricas. A cada 15 segundos, ele lê o endereço `/actuator/prometheus` de cada um dos seis serviços Java e guarda os números ao longo do tempo: requisições, tempo de resposta, memória, conexões com o banco e outros.

**Por que usar:** um *health check* diz apenas se o serviço está de pé **agora**. As métricas mostram **tendências** ("as respostas estão ficando lentas?", "a memória está subindo?") e ajudam a investigar problemas sem olhar dados pessoais.

**Como usar:**

1. Com o ambiente local no ar, abra **http://127.0.0.1:9090**.
2. Em **Status → Targets**, os seis serviços devem aparecer como **UP**.
3. Na página inicial (**Query**), digite uma consulta PromQL e clique em **Execute**. A aba **Graph** mostra a curva ao longo do tempo.

Consultas úteis:

```promql
# 1 = serviço respondendo, 0 = fora do ar
up{job="nexfleet-java"}

# Requisições por segundo, por serviço (últimos 5 minutos)
sum by (application) (rate(http_server_requests_seconds_count[5m]))

# Tempo médio de resposta, por serviço, em segundos
sum by (application) (rate(http_server_requests_seconds_sum[5m]))
  / sum by (application) (rate(http_server_requests_seconds_count[5m]))

# Respostas de erro 5xx por segundo
sum by (application) (rate(http_server_requests_seconds_count{status=~"5.."}[5m]))

# Memória heap usada pela JVM, em MB
sum by (application) (jvm_memory_used_bytes{area="heap"}) / 1024 / 1024

# Conexões ativas com o banco (pool Hikari)
sum by (application) (hikaricp_connections_active)
```

`./scripts/Test-Observability.ps1` confere automaticamente se os seis alvos estão UP.

**Na Azure:** não há Prometheus. Os serviços mandam logs e métricas para o **Log Analytics** e o **Application Insights**: portal Azure → Application Insights `appi-nexfleet-homolog-…`, ou Log Analytics → *Logs*. Exemplo de consulta (KQL) com os tempos medidos dentro de cada serviço:

```kusto
ContainerAppConsoleLogs_CL
| where TimeGenerated > ago(1h) and Log_s has "http_request_completed"
| extend ms = toint(extract(@"durationMs=(\d+)", 1, Log_s))
| summarize p95 = percentile(ms, 95), total = count() by ContainerAppName_s
```

---

## 7. Onde aprender mais

| Assunto | Documento |
|---|---|
| Estrutura de pastas e componentes | [GUIA-ESTRUTURA-PROJETO.md](GUIA-ESTRUTURA-PROJETO.md) |
| Execução local detalhada | [GUIA-EXECUCAO-LOCAL.md](GUIA-EXECUCAO-LOCAL.md) |
| Segurança dos bancos locais | [GUIA-SEGURANCA-BANCO-LOCAL.md](GUIA-SEGURANCA-BANCO-LOCAL.md) |
| Publicação na Azure (scripts e ordem) | [GUIA-INFRAESTRUTURA-AZURE-BICEP.md](GUIA-INFRAESTRUTURA-AZURE-BICEP.md), seção 7.1 |
| Decisões de arquitetura | [docs/adr](adr) (ADR 0001 a 0037) |
| Aulas passo a passo | [docs/tutorials](tutorials), em especial a 12 (outbox), a 13 (RabbitMQ), a 15 (DLQ), a 18 (Função) e a 19 (Prometheus) |
| Provas de qualidade CQ01–CQ12 | [MATRIZ-CQ01-CQ12.md](MATRIZ-CQ01-CQ12.md) e arquivos `EVIDENCIA-*` |
