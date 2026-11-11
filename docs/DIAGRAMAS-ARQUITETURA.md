# Diagramas de arquitetura do NexFleet

Versão de referência: **v1.0.0**, revisada em 11/11/2026.

Este documento representa a implementação existente nos nove repositórios (`nexfleet` e `nexfleet-*`). Ele atualiza as figuras C4, UML e DER do documento normativo sem alterar o PDF original. Nomes de processos, classes, rotas, tabelas e coleções foram conferidos contra o código Java, o Docker Compose do guarda-chuva, o Bicep, as migrações Flyway e os adaptadores MongoDB.

## Convenções e limites

- Setas contínuas representam chamadas síncronas HTTP, JDBC ou do driver MongoDB.
- Setas identificadas como evento representam comunicação assíncrona: RabbitMQ no ambiente local e Azure Service Bus na Azure (`MESSAGING_PROVIDER`).
- A Frota guarda seus dados no MongoDB (Atlas M0 na nuvem, `mongo:7.0` local). Identidade, Operações, Indicadores e a Function de notificação usam um único banco SQL Server/Azure SQL, **cada um no próprio schema e com o próprio usuário**, sem permissão nos schemas dos outros (ADR 0040).
- UUIDs de outro domínio são referências lógicas; não existem chaves estrangeiras entre schemas nem entre o SQL e o MongoDB.
- A Function envia e-mail pelo Azure Communication Services quando `notificationRecipientEmail` está configurado (ADR 0036); localmente, apenas captura a notificação no schema `notificacoes`.
- A borda pública na Azure é o APIM (API) e o Static Web Apps (telas e `/docs/eventos`). Localmente, o Gateway em `127.0.0.1:8080` é a entrada das APIs.

## C4 — nível 1: contexto do sistema

```mermaid
flowchart LR
  administrador["Administrador<br/>gerencia usuários, cadastros e consultas"]
  gestor["Gestor de Frota<br/>registra operações e consulta indicadores"]
  nexfleet["NexFleet<br/>gestão e controle de frotas"]
  email["Azure Communication Services Email<br/>notificação de abastecimento"]
  atlas["MongoDB Atlas<br/>banco da Frota (terceiro)"]

  administrador -->|HTTPS| nexfleet
  gestor -->|HTTPS| nexfleet
  nexfleet -->|e-mail por identidade gerenciada| email
  nexfleet -->|TLS| atlas
```

O motorista é uma entidade de negócio no MVP, sem login próprio. No ambiente local, o acesso web usa HTTP ligado a `127.0.0.1`; HTTPS pertence à publicação Azure.

## C4 — nível 2: contêineres e propriedade dos dados

```mermaid
flowchart TB
  pessoa["Administrador / Gestor"]

  subgraph web["Interface React + TypeScript + Vite (nexfleet-frontend)"]
    shell["Shell Web<br/>login, sessão e navegação"]
    mfeFrota["MFE Frota<br/>veículos, motoristas e vínculos"]
    mfeOperacoes["MFE Operações<br/>abastecimentos e manutenções"]
    mfePainel["MFE Painel<br/>dashboard e visão consolidada"]
  end

  gateway["API Gateway<br/>Spring Cloud Gateway + Swagger UI"]
  bff["BFF Web<br/>Spring Boot"]
  identidade["Identidade<br/>Spring Boot"]
  frota["Frota<br/>Spring Boot"]
  operacoes["Operações<br/>Spring Boot"]
  indicadores["Indicadores<br/>Spring Boot"]
  broker["RabbitMQ (local) / Service Bus (Azure)<br/>eventos, retry e DLQ"]
  function["Azure Function<br/>NotificarAbastecimento + CalcularEficiencia"]

  mongo[("MongoDB<br/>veiculos, motoristas, vinculos")]
  subgraph sql["SQL Server / Azure SQL — banco nexfleet"]
    schIdentidade[("schema identidade")]
    schOperacoes[("schema operacoes")]
    schIndicadores[("schema indicadores")]
    schNotificacoes[("schema notificacoes")]
  end

  pessoa --> shell
  shell --> mfeFrota
  shell --> mfeOperacoes
  shell --> mfePainel
  shell -->|REST JSON| gateway
  mfeFrota -->|REST JSON| gateway
  mfeOperacoes -->|REST JSON| gateway
  mfePainel -->|REST JSON| gateway
  gateway --> bff
  bff --> identidade
  bff --> frota
  bff --> operacoes
  bff --> indicadores
  bff -->|POST /api/calcular-eficiencia + chave| function
  operacoes -->|validação síncrona de referência| frota

  identidade --> schIdentidade
  frota --> mongo
  operacoes --> schOperacoes
  indicadores --> schIndicadores
  function --> schNotificacoes

  operacoes -->|eventos após commit| broker
  broker --> indicadores
  broker --> function
```

O Gateway é a única entrada das APIs; na Azure ele fica atrás do APIM. O BFF adapta os contratos para a interface, mas não acessa bancos de domínio. O dashboard é composto pelo BFF com dados de Frota e Indicadores; a visão consolidada (`GET /aggregated-data`) com Frota, Operações e a Function `CalcularEficiencia` (ADR 0041).

## C4 — nível 3: componentes do serviço Operações

```mermaid
flowchart LR
  bff["BFF Web"]
  frota["API Frota"]
  broker["RabbitMQ / Service Bus"]
  db[("Azure SQL<br/>schema operacoes")]

  subgraph api["api"]
    abastecimentosController["AbastecimentosController"]
    manutencoesController["ManutencoesController"]
  end

  subgraph application["application"]
    gerenciarAbastecimentos["GerenciarAbastecimentos"]
    abastecimentosPort["Abastecimentos<br/>porta"]
    referenciasFrotaPort["ReferenciasFrota<br/>porta"]
    gerenciarManutencoes["GerenciarManutencoes"]
    manutencoesPort["Manutencoes<br/>porta"]
    publicarPendentes["PublicarEventosPendentes"]
    eventosOutboxPort["EventosOutbox<br/>porta"]
    publicadorPort["PublicadorEventos<br/>porta"]
  end

  subgraph infrastructure["infrastructure"]
    jdbcAbastecimentos["JdbcAbastecimentos"]
    httpReferencias["HttpReferenciasFrota"]
    jdbcManutencoes["JdbcManutencoes"]
    outboxJob["OutboxPublicacaoJob"]
    jdbcOutbox["JdbcEventosOutbox"]
    rabbitPublisher["RabbitPublicadorEventos"]
    serviceBusPublisher["ServiceBusPublicadorEventos"]
  end

  bff --> abastecimentosController
  bff --> manutencoesController
  abastecimentosController --> gerenciarAbastecimentos
  manutencoesController --> gerenciarManutencoes
  gerenciarAbastecimentos --> abastecimentosPort
  gerenciarAbastecimentos --> referenciasFrotaPort
  gerenciarManutencoes --> manutencoesPort
  referenciasFrotaPort -.-> httpReferencias
  abastecimentosPort -.-> jdbcAbastecimentos
  manutencoesPort -.-> jdbcManutencoes
  httpReferencias --> frota
  jdbcAbastecimentos --> db
  jdbcManutencoes --> db
  outboxJob --> publicarPendentes
  publicarPendentes --> eventosOutboxPort
  publicarPendentes --> publicadorPort
  eventosOutboxPort -.-> jdbcOutbox
  publicadorPort -.-> rabbitPublisher
  publicadorPort -.-> serviceBusPublisher
  jdbcOutbox --> db
  rabbitPublisher --> broker
  serviceBusPublisher --> broker
```

As interfaces em `application` são portas; os adaptadores em `infrastructure` as implementam. A transação de abastecimento está no método `JdbcAbastecimentos.registrar`, que grava hodômetro, abastecimento e outbox no mesmo schema. `JdbcEventosOutbox` bloqueia o lote com `WITH (INDEX(ix_outbox_pendente), UPDLOCK, READPAST, ROWLOCK)`, na ordem `proxima_tentativa_em, ocorrido_em, id` (ADR 0040). O publicador é escolhido por `MESSAGING_PROVIDER`.

## C4 — nível 4: código da fatia Registrar Abastecimento

```mermaid
classDiagram
  class AbastecimentosController {
    -GerenciarAbastecimentos abastecimentos
    +listar(jwt, veiculoId, pagina, tamanho)
    +registrar(jwt, token, entrada)
  }
  class GerenciarAbastecimentos {
    -Abastecimentos abastecimentos
    -ReferenciasFrota frota
    -Clock relogio
    +registrar(perfil, autor, token, entrada)
    +listar(perfil, veiculoId, pagina, tamanho)
  }
  class Abastecimentos {
    <<interface>>
    +registrar(...)
    +listar(veiculoId, offset, limite)
  }
  class ReferenciasFrota {
    <<interface>>
    +operacaoPermitida(token, veiculoId, motoristaId, realizadoEm)
  }
  class JdbcAbastecimentos {
    -JdbcTemplate jdbc
    +registrar(...)
    +listar(veiculoId, offset, limite)
  }
  class HttpReferenciasFrota {
    -RestClient client
    +operacaoPermitida(token, veiculoId, motoristaId, data)
  }
  class FalhaAbastecimento

  AbastecimentosController --> GerenciarAbastecimentos
  GerenciarAbastecimentos --> Abastecimentos
  GerenciarAbastecimentos --> ReferenciasFrota
  JdbcAbastecimentos ..|> Abastecimentos
  HttpReferenciasFrota ..|> ReferenciasFrota
  GerenciarAbastecimentos ..> FalhaAbastecimento
  JdbcAbastecimentos ..> FalhaAbastecimento
  HttpReferenciasFrota ..> FalhaAbastecimento
```

A fatia usa JDBC com T-SQL e não possui um pacote `domain` próprio; suas regras estão no caso de uso e no adaptador transacional. Os tipos de domínio compartilhados existentes ficam em fatias específicas, como `StatusVeiculo`, `StatusMotorista` e `Perfil`.

## UML de componentes: fluxo entre serviços

```mermaid
flowchart LR
  shell["&lt;&lt;component&gt;&gt;<br/>Shell + MFEs"]
  gateway["&lt;&lt;component&gt;&gt;<br/>API Gateway"]
  bff["&lt;&lt;component&gt;&gt;<br/>BFF Web"]
  identidade["&lt;&lt;component&gt;&gt;<br/>Identidade"]
  frota["&lt;&lt;component&gt;&gt;<br/>Frota"]
  operacoes["&lt;&lt;component&gt;&gt;<br/>Operações"]
  indicadores["&lt;&lt;component&gt;&gt;<br/>Indicadores"]
  broker["&lt;&lt;component&gt;&gt;<br/>RabbitMQ / Service Bus"]
  notificar["&lt;&lt;component&gt;&gt;<br/>NotificarAbastecimento"]
  eficiencia["&lt;&lt;component&gt;&gt;<br/>CalcularEficiencia"]

  shell -->|OpenAPI público| gateway
  gateway -->|rotas explícitas| bff
  bff -->|HTTP interno| identidade
  bff -->|HTTP interno| frota
  bff -->|HTTP interno| operacoes
  bff -->|HTTP interno| indicadores
  bff -->|HTTP com chave da função| eficiencia
  operacoes -->|validação de vínculo/veículo| frota
  operacoes -->|AsyncAPI v1| broker
  broker --> indicadores
  broker --> notificar
```

Componentes verificados no código: `GatewayConfig`, `AbastecimentosWebController`, `GerenciarAbastecimentosWeb`, `HttpAbastecimentos`, `RabbitAbastecimentoListener`, `ServiceBusEventoListener`, `NotificarAbastecimentoFunction`, `CalcularEficienciaFunction`, `AgregadoController`, `ConsultarAgregado` e `HttpEficiencia`.

## UML de sequência: login e emissão do JWT

```mermaid
sequenceDiagram
  actor Usuario
  participant Shell
  participant Gateway
  participant BFF
  participant Identidade
  participant Banco as Azure SQL (schema identidade)

  Usuario->>Shell: informa e-mail e senha
  Shell->>Gateway: POST /api/v1/auth/login
  Gateway->>BFF: encaminha requisição
  BFF->>Identidade: POST /api/v1/identidade/login
  Identidade->>Banco: busca usuário ativo por e-mail
  Banco-->>Identidade: id, senha_hash, perfil
  Identidade->>Identidade: BCrypt verifica a senha
  Identidade->>Identidade: assina JWT RSA
  Identidade-->>BFF: token, expiração e perfil
  BFF-->>Gateway: resposta sem cache
  Gateway-->>Shell: 200 + JWT
  Shell-->>Usuario: sessão mantida somente em memória
```

## UML de sequência: abastecimento confirmado e evento assíncrono

```mermaid
sequenceDiagram
  actor Usuario
  participant MFE as MFE Operações
  participant Gateway
  participant BFF
  participant Operacoes as Serviço Operações
  participant Frota as Serviço Frota
  participant Banco as Azure SQL (schema operacoes)
  participant Job as OutboxPublicacaoJob
  participant Broker as RabbitMQ / Service Bus
  participant Indicadores
  participant Function as Azure Function

  Usuario->>MFE: confirma abastecimento
  MFE->>Gateway: POST /api/v1/abastecimentos + Bearer
  Gateway->>BFF: encaminha com X-Correlation-ID
  BFF->>Operacoes: POST /api/v1/operacoes/abastecimentos
  Operacoes->>Frota: valida veículo, motorista e vínculo na data
  Frota-->>Operacoes: válido
  Operacoes->>Banco: BEGIN TRANSACTION
  Operacoes->>Banco: SELECT hodômetro WITH (UPDLOCK, ROWLOCK)
  Operacoes->>Banco: INSERT abastecimento
  Operacoes->>Banco: UPDATE hodômetro
  Operacoes->>Banco: INSERT outbox_evento
  Operacoes->>Banco: COMMIT
  Operacoes-->>BFF: 201 Created
  BFF-->>Gateway: 201 Created
  Gateway-->>MFE: 201 + X-Correlation-ID
  MFE-->>Usuario: confirmação de sucesso

  Job->>Banco: bloqueia pendentes (UPDLOCK, READPAST)
  Banco-->>Job: AbastecimentoRegistrado v1
  Job->>Broker: publica mensagem persistente
  Broker-->>Job: confirmação
  Job->>Banco: marca publicado_em
  Broker->>Indicadores: entrega evento
  Indicadores->>Indicadores: projeta uma vez por evento_id
  Broker->>Function: entrega evento
  Function->>Function: notifica uma vez por evento_id
```

## UML de sequência: quilometragem regressiva

```mermaid
sequenceDiagram
  participant BFF
  participant Operacoes as Serviço Operações
  participant Frota as Serviço Frota
  participant Banco as Azure SQL (schema operacoes)

  BFF->>Operacoes: POST abastecimento (km menor)
  Operacoes->>Frota: valida referências
  Frota-->>Operacoes: válido
  Operacoes->>Banco: BEGIN TRANSACTION
  Operacoes->>Banco: SELECT hodômetro WITH (UPDLOCK, ROWLOCK)
  Banco-->>Operacoes: quilometragem atual maior
  Operacoes->>Banco: ROLLBACK
  Operacoes-->>BFF: 422 sem nova linha
  Note over Banco: abastecimento, hodômetro e outbox permanecem inalterados
```

## UML de sequência: visão consolidada (`GET /aggregated-data`)

```mermaid
sequenceDiagram
  participant Painel as MFE Painel
  participant Gateway
  participant BFF as BFF (ConsultarAgregado)
  participant Frota
  participant Operacoes as Operações
  participant Function as CalcularEficiencia

  Painel->>Gateway: GET /api/v1/aggregated-data + Bearer
  Gateway->>BFF: encaminha
  par timeout por fonte (padrão 5 s)
    BFF->>Frota: veículos, motoristas e vínculos (páginas de 100)
    Frota-->>BFF: listas
  and
    BFF->>Operacoes: abastecimentos e manutenções (até 4.000 de cada)
    Operacoes-->>BFF: históricos
  end
  BFF->>Function: POST /api/calcular-eficiencia (depois de Operações)
  Function-->>BFF: eficiência por veículo e da frota
  BFF-->>Gateway: 200 frota, operacoes, eficiencia, fontes, geradoEm
  Gateway-->>Painel: 200
  Note over BFF: fonte que falha ou estoura o tempo vem vazia com fontes.<fonte>="falhou"; as três falhando, 502
```

## DER físico: visão distribuída

Não existe um DER físico único. As tabelas abaixo são derivadas das migrações Flyway `V1` de cada serviço, todas no mesmo banco `nexfleet`, uma por schema. As coleções da Frota vêm dos adaptadores MongoDB de `nexfleet-frota` (`IndicesMongo`, `MongoVeiculos`, `MongoMotoristas`, `MongoVinculos`).

| Proprietário | Armazenamento | Tabelas ou coleções de negócio |
|---|---|---|
| Identidade | Azure SQL, schema `identidade` | `identidade.usuario` |
| Frota | MongoDB, banco `frota` | coleções `veiculos`, `motoristas`, `vinculos` |
| Operações | Azure SQL, schema `operacoes` | `operacoes.hodometro`, `operacoes.abastecimento`, `operacoes.outbox_evento`, `operacoes.manutencao` |
| Indicadores | Azure SQL, schema `indicadores` | `indicadores.abastecimento_projecao`, `indicadores.manutencao_projecao` |
| Notificações (Function) | Azure SQL, schema `notificacoes` | `notificacoes.email_capturado` |

As tabelas internas do Flyway (`flyway_schema_history` em cada schema) não fazem parte do modelo de negócio.

### DER — Identidade

```mermaid
erDiagram
  IDENTIDADE_USUARIO {
    uniqueidentifier id PK
    nvarchar email UK
    varchar senha_hash
    bit ativo
    varchar perfil
  }
```

`email` é normalizado e único; `senha_hash` deve ter formato BCrypt; `perfil` aceita `ADMINISTRADOR` ou `GESTOR_FROTA`.

### Modelo de documentos — Frota (MongoDB)

```mermaid
erDiagram
  VEICULOS ||--o{ VINCULOS : "veiculoId (lógico)"
  MOTORISTAS ||--o{ VINCULOS : "motoristaId (lógico)"

  VEICULOS {
    string _id PK "UUID"
    string placa UK
    string marca
    string modelo
    int ano
    string tipo
    long quilometragem
    string status
    string dataAquisicao
    string criadoPor
    string atualizadoPor
    date criadoEm
    date atualizadoEm
  }
  MOTORISTAS {
    string _id PK "UUID"
    string nome
    string cpf UK
    string cnh UK
    string categoria
    string validadeCnh
    string telefone
    string status
    string criadoPor
    string atualizadoPor
    date criadoEm
    date atualizadoEm
  }
  VINCULOS {
    string _id PK "UUID"
    string veiculoId
    string motoristaId
    date inicio
    date fim
    bool ativo
    string criadoPor
    string encerradoPor
    date criadoEm
    date atualizadoEm
  }
```

Não há chave estrangeira: `veiculoId` e `motoristaId` são UUIDs em texto. Índices únicos: `ux_veiculo_placa`, `ux_motorista_cpf`, `ux_motorista_cnh` e `ux_vinculo_veiculo_ativo`, este parcial (`{ativo: true}`), que permite no máximo um vínculo ativo por veículo. Vínculos encerrados permanecem no histórico (ADR 0039).

### DER — Operações

```mermaid
erDiagram
  OPERACOES_HODOMETRO ||--o{ OPERACOES_ABASTECIMENTO : "mesmo veiculo_id"
  OPERACOES_ABASTECIMENTO ||--|| OPERACOES_OUTBOX_EVENTO : "agregado lógico"
  OPERACOES_HODOMETRO ||--o{ OPERACOES_MANUTENCAO : "mesmo veiculo_id"
  OPERACOES_MANUTENCAO ||--|| OPERACOES_OUTBOX_EVENTO : "agregado lógico"

  OPERACOES_HODOMETRO {
    uniqueidentifier veiculo_id PK
    bigint quilometragem
    datetimeoffset atualizado_em
  }
  OPERACOES_ABASTECIMENTO {
    uniqueidentifier id PK
    uniqueidentifier veiculo_id
    uniqueidentifier motorista_id
    datetimeoffset realizado_em
    nvarchar combustivel
    numeric litros
    numeric valor_total
    bigint quilometragem
    uniqueidentifier criado_por
    datetimeoffset criado_em
  }
  OPERACOES_OUTBOX_EVENTO {
    uniqueidentifier id PK
    nvarchar agregado_tipo
    uniqueidentifier agregado_id
    nvarchar evento_tipo
    int evento_versao
    uniqueidentifier correlation_id
    nvarchar payload "NVARCHAR(MAX), ISJSON"
    datetimeoffset ocorrido_em
    datetimeoffset publicado_em
    int tentativas
    nvarchar ultimo_erro
    datetimeoffset proxima_tentativa_em
  }
  OPERACOES_MANUTENCAO {
    uniqueidentifier id PK
    uniqueidentifier veiculo_id
    nvarchar tipo
    date realizada_em
    bigint quilometragem
    nvarchar descricao
    nvarchar oficina
    numeric valor
    date proxima_manutencao
    uniqueidentifier criado_por
    datetimeoffset criado_em
  }
```

As linhas do diagrama representam relações lógicas por UUID. Cada abastecimento ou manutenção registrado gera seu próprio evento; `agregado_tipo` identifica qual das duas relações se aplica. A migração não cria FKs entre essas tabelas; a consistência crítica de abastecimento, hodômetro e outbox é protegida pela transação e pelo bloqueio `UPDLOCK` do hodômetro. O índice filtrado `ix_outbox_pendente (proxima_tentativa_em, ocorrido_em, id) WHERE publicado_em IS NULL` atende o publicador. `veiculo_id` e `motorista_id` não apontam para a Frota, que está em outro banco.

### DER — Indicadores

```mermaid
erDiagram
  INDICADORES_ABASTECIMENTO_PROJECAO {
    uniqueidentifier evento_id PK
    uniqueidentifier abastecimento_id UK
    uniqueidentifier veiculo_id
    uniqueidentifier motorista_id
    datetimeoffset realizado_em
    nvarchar combustivel
    numeric litros
    numeric valor_total
    bigint quilometragem
    datetimeoffset recebido_em
  }
  INDICADORES_MANUTENCAO_PROJECAO {
    uniqueidentifier evento_id PK
    uniqueidentifier manutencao_id UK
    uniqueidentifier veiculo_id
    nvarchar tipo
    date realizada_em
    bigint quilometragem
    nvarchar descricao
    nvarchar oficina
    numeric valor
    date proxima_manutencao
    datetimeoffset recebido_em
  }
```

`evento_id` torna o consumo idempotente. As projeções são reconstruíveis a partir dos eventos e não possuem FKs para Operações ou Frota.

### DER — Notificações

```mermaid
erDiagram
  NOTIFICACOES_EMAIL_CAPTURADO {
    uniqueidentifier evento_id PK
    uniqueidentifier abastecimento_id
    nvarchar assunto
    nvarchar corpo "NVARCHAR(MAX)"
    nvarchar status
    datetimeoffset solicitado_em
    nvarchar destinatario
    nvarchar provedor
    nvarchar provedor_mensagem_id
    datetimeoffset enviado_em
    nvarchar erro_ultimo
  }
```

`evento_id` como chave primária reserva cada notificação uma única vez (`ReservaIdempotente`). Localmente, o provedor `captured-local` (`JdbcProvedorEmailCapturado`) só grava a notificação; na Azure, `AzureCommunicationProvedorEmail` envia o e-mail e registra o resultado.

## Rastreabilidade entre diagrama e código

| Visão | Fontes verificadas |
|---|---|
| C4 nível 1 | requisitos do produto, escopo, atores e ADRs 0036 e 0039 |
| C4 nível 2 | `compose.yaml`, `infra/azure/modules/*.bicep`, shell e três MFEs de `nexfleet-frontend` |
| C4 nível 3 | pacotes de `nexfleet-operacoes/src/main/java` |
| C4 nível 4 | `AbastecimentosController`, `GerenciarAbastecimentos`, `Abastecimentos`, `ReferenciasFrota`, `JdbcAbastecimentos`, `HttpReferenciasFrota` |
| UML de componentes | `GatewayConfig`, `AbastecimentosWebController`, `GerenciarAbastecimentosWeb`, `HttpAbastecimentos`, `RabbitAbastecimentoListener`, `NotificarAbastecimentoFunction`, `CalcularEficienciaFunction` e `ConsultarAgregado` |
| UML de sequência | `OutboxPublicacaoJob`, `PublicarEventosPendentes`, `RabbitPublicadorEventos`, `JdbcEventosOutbox`, `ProjetarAbastecimento`, `JdbcProjecoesAbastecimento`, `NotificarAbastecimento`, `JdbcProvedorEmailCapturado`, `ConsultarAgregado` e `HttpEficiencia` |
| DER | migrações `V1` em `nexfleet-{identidade,operacoes,indicadores,function}/src/main/resources/db/migration` e adaptadores `Mongo*` de `nexfleet-frota` |

## Regra de manutenção

Uma mudança em rota, fronteira de serviço, nome de classe relevante, evento, migração ou coleção deve atualizar este arquivo na mesma entrega. O módulo `quality` verifica a presença dos níveis C4, das visões UML, das oito tabelas de negócio migradas (a Frota não tem migração SQL) e das principais classes do fluxo crítico, comparando-as com os repositórios irmãos (`-Dnexfleet.repos.dir`).
