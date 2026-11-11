# Aula 18 — Function serverless, idempotência e DLQ

## O que foi construído

Quando Operações confirma um abastecimento, o evento segue este caminho:

```text
Operações → outbox → RabbitMQ → fila de notificações → Azure Function
                                                        ↓
                                           PostgreSQL de notificações
```

A Function recebe `AbastecimentoRegistrado.v1`, valida os campos, prepara assunto/corpo e pede ao `ProvedorEmail` que processe a solicitação. Localmente, o adaptador grava essa solicitação para que possamos verificá-la sem usar uma conta de e-mail real.

## O que é serverless

Serverless não significa “sem servidor”. Significa que o provedor executa a função quando um gatilho ocorre e cuida da infraestrutura do runtime. Aqui, o gatilho é uma mensagem. Na máquina local usamos a mesma aplicação dentro do runtime oficial de Azure Functions.

## Por que a notificação fica fora de Operações

Registrar abastecimento é a tarefa principal; enviar aviso é consequência. Se os dois ficassem na mesma chamada, indisponibilidade do provedor de e-mail poderia atrasar ou negar um abastecimento válido. Com EDA, Operações responde depois do próprio commit, e a notificação acontece depois.

Use essa separação para tarefas secundárias, como avisos, auditoria e atualização de projeções. Não a use quando a decisão precisa acontecer antes de confirmar o comando.

## O que é idempotência

RabbitMQ pode entregar a mesma mensagem novamente. Uma operação idempotente produz o mesmo estado final mesmo quando repetida. A tabela usa `evento_id` como chave primária, e o SQL contém:

```sql
ON CONFLICT (evento_id) DO NOTHING
```

Assim, duas cópias do mesmo evento deixam um único registro. O teste `Test-Sprint3Serverless.ps1` publica a mesma mensagem duas vezes e consulta o banco.

## Retry e DLQ

Quando o JSON é inválido, a Function lança uma exceção. A fila quorum conta as entregas. Depois do limite de três, o RabbitMQ envia a mensagem ao dead-letter exchange, que a roteia para a DLQ.

A DLQ é uma área de quarentena. Ela evita que uma mensagem defeituosa bloqueie as seguintes e preserva evidência para análise. Reprocessar uma DLQ deve ser uma ação consciente depois de corrigir a causa.

## Como Clean Architecture aparece

- `application/NotificarAbastecimento`: regra e validação, sem Azure, JDBC ou RabbitMQ;
- `application/ProvedorEmail`: porta que descreve o que o caso de uso precisa;
- `infrastructure/JdbcProvedorEmailCapturado`: adaptador local idempotente;
- `api/NotificarAbastecimentoFunction`: traduz a mensagem do runtime para a entrada do caso de uso;
- `config/CompositionRoot`: liga porta e adaptador.

As regras ArchUnit impedem aplicação → framework, API → persistência e infraestrutura → API.

## Como Vertical Slice aparece

Todo o comportamento está dentro de `notificarabastecimento`. Em vez de espalhar a função por pastas genéricas de controladores, serviços e repositórios, a fatia agrupa as camadas necessárias a um objetivo: notificar um abastecimento.

## Por que Flyway roda antes da Function

Migração altera a estrutura do banco. Ela deve terminar antes de aceitar eventos. Executá-la no primeiro evento aumenta o cold start e várias instâncias podem tentar fazer a mesma preparação. O Compose usa `notificacoes-migrations` e só inicia a Function depois de seu término bem-sucedido.

## Para que serve o Azurite

O host do Azure Functions usa armazenamento para coordenação e estado interno. Azurite emula Blob, Queue e Table Storage localmente. Ele não guarda os e-mails; o PostgreSQL de notificações faz isso. Na nuvem, `AzureWebJobsStorage` será uma conexão segura com uma Storage Account.

## Como testar

Com o ambiente iniciado:

```powershell
./scripts/Test-Sprint3Serverless.ps1
```

O teste espera o consumidor, publica uma duplicata, exige uma única gravação, publica JSON inválido e exige aumento da DLQ.

## Limite desta entrega

“Capturado localmente” não significa “entregue por e-mail”. O PJBL não define destinatário ou provedor. A Sprint 4 escolherá e configurará um adaptador externo, segredos, telemetria e hospedagem Azure sem mudar a regra central.
