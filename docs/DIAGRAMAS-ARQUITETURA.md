# Diagramas de arquitetura do NexFleet

Versão de referência: **v0.24.0**, revisada em 08/11/2026.

Este documento representa a implementação existente no repositório. Ele atualiza as figuras C4, UML e DER do documento normativo sem alterar o PDF original. Nomes de processos, classes, rotas e tabelas foram conferidos contra o código Java, o Docker Compose e as migrações Flyway.

## Convenções e limites

- Setas contínuas representam chamadas síncronas HTTP ou JDBC.
- Setas identificadas como evento representam comunicação assíncrona pelo RabbitMQ.
- Cada microsserviço acessa somente seu próprio banco PostgreSQL.
- UUIDs de outro domínio são referências lógicas; não existem chaves estrangeiras entre bancos.
- A Function registra uma notificação capturada localmente. Azure Communication Services Email foi recomendado, mas ainda não foi autorizado nem configurado.
- Azure é a implantação futura. Os diagramas abaixo descrevem o ambiente implementado e comprovado localmente.

## C4 — nível 1: contexto do sistema

```mermaid
flowchart LR
  administrador["Administrador<br/>gerencia usuários, cadastros e consultas"]
  gestor["Gestor de Frota<br/>registra operações e consulta indicadores"]
  nexfleet["NexFleet<br/>gestão e controle de frotas"]
  email["Provedor externo de e-mail<br/>decisão futura"]

  administrador -->|HTTPS no ambiente publicado| nexfleet
  gestor -->|HTTPS no ambiente publicado| nexfleet
  nexfleet -.->|integração ainda não implementada| email
```

O motorista é uma entidade de negócio no MVP, sem login próprio. No ambiente local, o acesso web usa HTTP ligado a `127.0.0.1`; HTTPS pertence à publicação Azure.

## C4 — nível 2: contêineres e propriedade dos dados

```mermaid
flowchart TB
  pessoa["Administrador / Gestor"]

  subgraph web["Interface React + TypeScript + Vite"]
    shell["Shell Web<br/>login, sessão e navegação"]
    mfeFrota["MFE Frota<br/>veículos, motoristas e vínculos"]
    mfeOperacoes["MFE Operações<br/>abastecimentos e manutenções"]
    mfePainel["MFE Painel<br/>dashboard"]
  end

  gateway["API Gateway<br/>Spring Cloud Gateway"]
  bff["BFF Web<br/>Spring Boot"]
  identidade["Identidade<br/>Spring Boot"]
  frota["Frota<br/>Spring Boot"]
  operacoes["Operações<br/>Spring Boot"]
  indicadores["Indicadores<br/>Spring Boot"]
  rabbit["RabbitMQ<br/>eventos, retry e DLQ"]
  function["Azure Function<br/>NotificarAbastecimento"]
  prometheus["Prometheus<br/>métricas locais"]

  dbIdentidade[("PostgreSQL<br/>Identidade")]
  dbFrota[("PostgreSQL<br/>Frota")]
  dbOperacoes[("PostgreSQL<br/>Operações")]
  dbIndicadores[("PostgreSQL<br/>Indicadores")]
  dbNotificacoes[("PostgreSQL<br/>Notificações")]

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
  operacoes -->|validação síncrona de referência| frota

  identidade --> dbIdentidade
  frota --> dbFrota
  operacoes --> dbOperacoes
  indicadores --> dbIndicadores
  function --> dbNotificacoes

  operacoes -->|eventos após commit| rabbit
  rabbit --> indicadores
  rabbit --> function

  prometheus -.->|scrape| gateway
  prometheus -.->|scrape interno| bff
  prometheus -.->|scrape interno| identidade
  prometheus -.->|scrape interno| frota
  prometheus -.->|scrape interno| operacoes
  prometheus -.->|scrape interno| indicadores
```

O Gateway é a única entrada pública das APIs no Compose. O BFF adapta os contratos para a interface, mas não acessa bancos de domínio. O dashboard é composto pelo BFF com dados de Frota e Indicadores.

## C4 — nível 3: componentes do serviço Operações

```mermaid
flowchart LR
  bff["BFF Web"]
  frota["API Frota"]
  rabbit["RabbitMQ"]
  db[("PostgreSQL Operações")]

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
  jdbcOutbox --> db
  rabbitPublisher --> rabbit
```

As interfaces em `application` são portas; os adaptadores em `infrastructure` as implementam. A transação de abastecimento está no método `JdbcAbastecimentos.registrar`, que grava hodômetro, abastecimento e outbox no mesmo banco.

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

Esta é a estrutura real da v0.24.0. A fatia usa JDBC e não possui um pacote `domain` próprio; suas regras estão no caso de uso e no adaptador transacional. Os tipos de domínio compartilhados existentes ficam em fatias específicas, como `StatusVeiculo`, `StatusMotorista` e `Perfil`.

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
  broker["&lt;&lt;component&gt;&gt;<br/>RabbitMQ"]
  function["&lt;&lt;component&gt;&gt;<br/>NotificarAbastecimento"]

  shell -->|OpenAPI público| gateway
  gateway -->|rotas explícitas| bff
  bff -->|HTTP interno| identidade
  bff -->|HTTP interno| frota
  bff -->|HTTP interno| operacoes
  bff -->|HTTP interno| indicadores
  operacoes -->|validação de vínculo/veículo| frota
  operacoes -->|AsyncAPI v1| broker
  broker --> indicadores
  broker --> function
```

## UML de sequência: login e emissão do JWT

```mermaid
sequenceDiagram
  actor Usuario
  participant Shell
  participant Gateway
  participant BFF
  participant Identidade
  participant Banco as PostgreSQL Identidade

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
  participant Banco as PostgreSQL Operações
  participant Job as OutboxPublicacaoJob
  participant Rabbit as RabbitMQ
  participant Indicadores
  participant Function as Azure Function

  Usuario->>MFE: confirma abastecimento
  MFE->>Gateway: POST /api/v1/abastecimentos + Bearer
  Gateway->>BFF: encaminha com X-Correlation-ID
  BFF->>Operacoes: POST /api/v1/operacoes/abastecimentos
  Operacoes->>Frota: valida veículo, motorista e vínculo na data
  Frota-->>Operacoes: válido
  Operacoes->>Banco: BEGIN
  Operacoes->>Banco: bloqueia/valida hodômetro
  Operacoes->>Banco: INSERT abastecimento
  Operacoes->>Banco: UPDATE hodômetro
  Operacoes->>Banco: INSERT outbox_evento
  Operacoes->>Banco: COMMIT
  Operacoes-->>BFF: 201 Created
  BFF-->>Gateway: 201 Created
  Gateway-->>MFE: 201 + X-Correlation-ID
  MFE-->>Usuario: confirmação de sucesso

  Job->>Banco: bloqueia eventos pendentes
  Banco-->>Job: AbastecimentoRegistrado v1
  Job->>Rabbit: publica mensagem persistente
  Rabbit-->>Job: publisher confirm
  Job->>Banco: marca publicado_em
  Rabbit->>Indicadores: entrega evento
  Indicadores->>Indicadores: projeta uma vez por evento_id
  Rabbit->>Function: entrega evento
  Function->>Function: captura uma vez por evento_id
```

## UML de sequência: quilometragem regressiva

```mermaid
sequenceDiagram
  participant BFF
  participant Operacoes as Serviço Operações
  participant Frota as Serviço Frota
  participant Banco as PostgreSQL Operações

  BFF->>Operacoes: POST abastecimento (km menor)
  Operacoes->>Frota: valida referências
  Frota-->>Operacoes: válido
  Operacoes->>Banco: BEGIN
  Operacoes->>Banco: SELECT hodômetro FOR UPDATE
  Banco-->>Operacoes: quilometragem atual maior
  Operacoes->>Banco: ROLLBACK
  Operacoes-->>BFF: 422 sem nova linha
  Note over Banco: abastecimento, hodômetro e outbox permanecem inalterados
```

## DER físico: visão distribuída

Não existe um DER físico único nem um banco compartilhado. A lista abaixo é derivada das migrações Flyway atuais.

| Banco proprietário | Tabelas de negócio |
|---|---|
| Identidade | `identidade.usuario` |
| Frota | `frota.veiculo`, `frota.motorista`, `frota.veiculo_motorista` |
| Operações | `operacoes.hodometro`, `operacoes.abastecimento`, `operacoes.outbox_evento`, `operacoes.manutencao` |
| Indicadores | `indicadores.abastecimento_projecao`, `indicadores.manutencao_projecao` |
| Notificações | `notificacoes.email_capturado` |

As tabelas internas do Flyway não fazem parte do modelo de negócio.

### DER — Identidade

```mermaid
erDiagram
  IDENTIDADE_USUARIO {
    uuid id PK
    varchar email UK
    varchar senha_hash
    boolean ativo
    varchar perfil
  }
```

`email` é normalizado e único; `senha_hash` deve ter formato BCrypt; `perfil` aceita `ADMINISTRADOR` ou `GESTOR_FROTA`.

### DER — Frota

```mermaid
erDiagram
  FROTA_VEICULO ||--o{ FROTA_VEICULO_MOTORISTA : possui
  FROTA_MOTORISTA ||--o{ FROTA_VEICULO_MOTORISTA : participa

  FROTA_VEICULO {
    uuid id PK
    varchar placa UK
    varchar marca
    varchar modelo
    integer ano
    varchar tipo
    bigint quilometragem
    varchar status
    date data_aquisicao
    uuid criado_por
    uuid atualizado_por
    timestamptz criado_em
    timestamptz atualizado_em
  }
  FROTA_MOTORISTA {
    uuid id PK
    varchar nome
    varchar cpf UK
    varchar cnh UK
    varchar categoria
    date validade_cnh
    varchar telefone
    varchar status
    uuid criado_por
    uuid atualizado_por
    timestamptz criado_em
    timestamptz atualizado_em
  }
  FROTA_VEICULO_MOTORISTA {
    uuid id PK
    uuid veiculo_id FK
    uuid motorista_id FK
    timestamptz inicio_em
    timestamptz fim_em
    uuid criado_por
    uuid encerrado_por
    timestamptz criado_em
    timestamptz atualizado_em
  }
```

As duas chaves estrangeiras pertencem ao próprio banco de Frota. Um índice parcial permite no máximo um vínculo ativo por veículo; vínculos encerrados permanecem no histórico.

### DER — Operações

```mermaid
erDiagram
  OPERACOES_HODOMETRO ||--o{ OPERACOES_ABASTECIMENTO : "mesmo veiculo_id"
  OPERACOES_ABASTECIMENTO ||--|| OPERACOES_OUTBOX_EVENTO : "agregado lógico"
  OPERACOES_HODOMETRO ||--o{ OPERACOES_MANUTENCAO : "mesmo veiculo_id"
  OPERACOES_MANUTENCAO ||--|| OPERACOES_OUTBOX_EVENTO : "agregado lógico"

  OPERACOES_HODOMETRO {
    uuid veiculo_id PK
    bigint quilometragem
    timestamptz atualizado_em
  }
  OPERACOES_ABASTECIMENTO {
    uuid id PK
    uuid veiculo_id
    uuid motorista_id
    timestamptz realizado_em
    varchar combustivel
    numeric litros
    numeric valor_total
    bigint quilometragem
    uuid criado_por
    timestamptz criado_em
  }
  OPERACOES_OUTBOX_EVENTO {
    uuid id PK
    varchar agregado_tipo
    uuid agregado_id
    varchar evento_tipo
    integer evento_versao
    uuid correlation_id
    jsonb payload
    timestamptz ocorrido_em
    timestamptz publicado_em
    integer tentativas
    varchar ultimo_erro
    timestamptz proxima_tentativa_em
  }
  OPERACOES_MANUTENCAO {
    uuid id PK
    uuid veiculo_id
    varchar tipo
    date realizada_em
    bigint quilometragem
    varchar descricao
    varchar oficina
    numeric valor
    date proxima_manutencao
    uuid criado_por
    timestamptz criado_em
  }
```

As linhas do diagrama representam relações lógicas por UUID. Cada abastecimento ou manutenção registrado gera seu próprio evento; `agregado_tipo` identifica qual das duas relações se aplica. As migrações atuais não criam FKs entre essas tabelas; a consistência crítica de abastecimento, hodômetro e outbox é protegida pela transação e pelo bloqueio `FOR UPDATE`. `veiculo_id` e `motorista_id` não apontam por FK para Frota porque pertencem a outro banco.

### DER — Indicadores

```mermaid
erDiagram
  INDICADORES_ABASTECIMENTO_PROJECAO {
    uuid evento_id PK
    uuid abastecimento_id UK
    uuid veiculo_id
    uuid motorista_id
    timestamptz realizado_em
    varchar combustivel
    numeric litros
    numeric valor_total
    bigint quilometragem
    timestamptz recebido_em
  }
  INDICADORES_MANUTENCAO_PROJECAO {
    uuid evento_id PK
    uuid manutencao_id UK
    uuid veiculo_id
    varchar tipo
    date realizada_em
    bigint quilometragem
    varchar descricao
    varchar oficina
    numeric valor
    date proxima_manutencao
    timestamptz recebido_em
  }
```

`evento_id` torna o consumo idempotente. As projeções são reconstruíveis a partir dos eventos e não possuem FKs para Operações ou Frota.

### DER — Notificações locais

```mermaid
erDiagram
  NOTIFICACOES_EMAIL_CAPTURADO {
    uuid evento_id PK
    uuid abastecimento_id
    varchar assunto
    text corpo
    varchar status
    timestamptz solicitado_em
  }
```

O status atual é sempre `CAPTURADO_LOCALMENTE`. Esta tabela não comprova envio de e-mail externo.

## Rastreabilidade entre diagrama e código

| Visão | Fontes verificadas |
|---|---|
| C4 nível 1 | `docs/reference/ArqCloud_PJBL-Completo.pdf`, escopo e atores |
| C4 nível 2 | `compose.sprint0.yaml`, `compose.jwt-rsa.yaml`, shell e três MFEs |
| C4 nível 3 | pacotes de `services/operacoes/src/main/java` |
| C4 nível 4 | `AbastecimentosController`, `GerenciarAbastecimentos`, `Abastecimentos`, `ReferenciasFrota`, `JdbcAbastecimentos`, `HttpReferenciasFrota` |
| UML de componentes | `GatewayConfig`, `AbastecimentosWebController`, `GerenciarAbastecimentosWeb`, `HttpAbastecimentos`, `RabbitAbastecimentoListener` e `NotificarAbastecimentoFunction` |
| UML de sequência | `OutboxPublicacaoJob`, `PublicarEventosPendentes`, `RabbitPublicadorEventos`, `ProjetarAbastecimento`, `JdbcProjecoesAbastecimento`, `NotificarAbastecimento` e `JdbcProvedorEmailCapturado` |
| DER | todas as migrações em `services/*/src/main/resources/db/migration` e `functions/notificar-abastecimento/src/main/resources/db/migration` |

## Regra de manutenção

Uma mudança em rota, fronteira de serviço, nome de classe relevante, evento ou migração deve atualizar este arquivo na mesma entrega. O módulo `quality` verifica a presença dos níveis C4, das visões UML, das onze tabelas de negócio migradas e das principais classes do fluxo crítico.
