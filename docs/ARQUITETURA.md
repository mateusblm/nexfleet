# Arquitetura-alvo do NexFleet

Atualização de 10/11/2026: a homologação foi publicada em `Central US` e validada. Estão no ar:

- Static Web Apps e APIM;
- seis Container Apps, a Function e o Service Bus;
- PostgreSQL privado;
- ACS Email, já ativo.

O Bicep modela 22/22 tipos. Ver as ADRs 0036 e 0037 e o [guia de uso e operação](GUIA-USO-E-OPERACAO.md).

Atualização v0.29.0 (09/11/2026): RabbitMQ permanece no desenvolvimento local e Service Bus torna-se o transporte configurável da Azure em Operações, Indicadores e Function. O Bicep passa a modelar 19/19 tipos, VNet/PostgreSQL privado, seis Container Apps, identidades e RBAC. O frontend pode ser empacotado para Static Web Apps e o adaptador de Azure Communication Services Email permanece desativado por padrão. Veja a ADR 0034, a Aula 33 e a [entrega v0.29.0](ENTREGA-v0.29.0.md).

Atualização v0.28.0 (08/11/2026): os cinco provedores autorizados foram registrados e um orçamento de R$ 100/mês foi configurado sem implantar workloads. `Brazil South`, `East US 2`, Service Bus e backup de sete dias foram aprovados. Azure Communication Services Email é a recomendação pendente de autorização. Veja a ADR 0033, a Aula 32 e o [guia de pré-publicação](GUIA-PRE-PUBLICACAO-AZURE.md).

Atualização v0.26.0 (08/11/2026): a fundação Azure passa a existir em Bicep compilável, com orçamento, observabilidade, dados, mensageria, Function Flex, identidade e borda. A trava `publicationApproved` é falsa por padrão e não há comando de implantação. Quinze dos 16 tipos estão modelados; Container Apps depende da migração cloud de RabbitMQ para Service Bus, rede e credenciais. Veja a ADR 0031, a Aula 30 e o [guia Bicep](GUIA-INFRAESTRUTURA-AZURE-BICEP.md).

Atualização v0.27.0 (08/11/2026): a descoberta conectada confirma `Brazil South` para 15 tipos e separa Static Web Apps em `staticWebLocation`. O perfil v3, o Bicep e o preflight representam as duas regiões sem registrar os cinco provedores pendentes. Veja a ADR 0032, a Aula 31 e o [guia de pré-publicação](GUIA-PRE-PUBLICACAO-AZURE.md).

Atualização v0.25.0 (08/11/2026): a publicação Azure passa a exigir um perfil local validado, orçamento e oito aprovações humanas. O preflight consulta assinatura, região e tipos de recurso sem registrar provedores ou criar infraestrutura. O modelo é validado na CI; a prova conectada depende do Azure CLI e das decisões reais. Veja a ADR 0030, a Aula 29 e o guia de pré-publicação Azure.

Atualização v0.24.0 (08/11/2026): C4 níveis 1–4, UML de componentes/classes/sequências e os cinco DERs físicos foram revisados contra processos, rotas, classes e as onze tabelas criadas por Flyway. A visão atual distingue relações lógicas de FKs reais e corrige a fatia Registrar Abastecimento para JDBC e os pacotes implementados. Veja os [diagramas correntes](DIAGRAMAS-ARQUITETURA.md), a ADR 0029 e a Aula 28.

Atualização v0.23.0 (08/11/2026): CQ07 passa a ser comprovado com o JAR real de Frota e PostgreSQL efêmero. Depois da parada controlada do banco, readiness e API técnica devolvem `DOWN/503`; a resposta e o log mantêm `X-Correlation-ID`, sem expor senha ou token sentinela. Veja a ADR 0028, a Aula 27 e a evidência CQ07.

Atualização v0.22.0 (08/11/2026): CQ05 passa a ser comprovado com bancos efêmeros e separados de Frota e Operações. A sequência cria o veículo, registra o abastecimento, inativa logicamente o cadastro e consulta novamente o histórico, preservando data e motorista responsável sem importações ou SQL entre serviços. Veja a ADR 0027, a Aula 26 e a evidência CQ05.

Atualização v0.21.0 (08/11/2026): CQ03 e CQ04 passam a ser comprovados em PostgreSQL efêmero com as migrações V1–V5. A prova percorre controller, caso de uso, proxy transacional e adaptador JDBC; uma constraint exclusiva do teste provoca falha na outbox e confirma rollback das três escritas. Veja a ADR 0026, a Aula 25 e a evidência CQ03/CQ04.

Atualização v0.20.0 (08/11/2026): CQ06 padroniza validação acessível nos sete formulários críticos, preservando dados válidos e relacionando campos incorretos a uma mensagem compreensível. A matriz CQ01–CQ12 passa a separar evidência aprovada de implementação ainda sem prova integrada exata. Veja a ADR 0025, a Aula 24, a evidência CQ06 e a matriz de qualidade.

Atualização v0.19.0 (08/11/2026): CQ09 mede 100 usuários nas listas paginadas; CQ10 cria dumps dos cinco bancos com manifesto/SHA-256 e os restaura em PostgreSQL temporários, sem tocar nos volumes ativos. Veja as ADRs 0023–0024, as Aulas 22–23 e as evidências CQ09/CQ10.

Atualização v0.16.0 (07/11/2026): o Gateway valida ou cria um UUID em `X-Correlation-ID`, o BFF e Operações o propagam nas chamadas internas, e todos os serviços o registram em logs seguros. A migração V5 persiste a correlação na outbox; o valor segue no payload e no cabeçalho RabbitMQ até Indicadores e a Azure Function. Eventos antigos usam `eventoId` como fallback. Veja a ADR 0021 e a Aula 20.

Atualização v0.15.0 (07/11/2026): os seis processos Java expõem métricas Micrometer no endpoint interno `/actuator/prometheus`. Um Prometheus LTS no Compose coleta os alvos a cada 15 segundos, retém sete dias e publica a interface apenas em `127.0.0.1:9090`. A rota de métricas não atravessa o API Gateway. Veja a ADR 0020 e a Aula 19.

O documento normativo é o [PJBL enviado pelo usuário](reference/ArqCloud_PJBL-Completo.pdf), preservado sem alterações. Veja [escopo e rastreabilidade](ESCOPO-PJBL.md). O PDF em `output/pdf` é histórico. Este resumo não substitui as regras do PJBL nem comprova que a arquitetura-alvo já esteja implementada.

Atualização v0.14.0 (06/11/2026): a Azure Function Java 21 `NotificarAbastecimento` consome `AbastecimentoRegistrado.v1` em fila própria. A fatia possui API de entrada, caso de uso e porta de saída, adaptador JDBC local e regras ArchUnit. O `evento_id` é chave primária, tornando a operação idempotente. A fila quorum limita a três entregas e encaminha falhas para DLQ. Flyway roda como etapa de implantação antes da Function; Azurite oferece o armazenamento interno do host apenas localmente. Veja a ADR 0019 e a Aula 18.

Atualização v0.13.0 (06/11/2026): a vertical slice `consultardashboard` usa as projeções próprias de Indicadores para custos e o contrato HTTP de Frota para status. O BFF compõe as respostas, sem SQL cruzado, e o microfrontend Painel apresenta gastos, situação e próximas manutenções pela rota pública do Gateway. Indicadores agora valida JWT RSA/JWKS. Veja a ADR 0018 e a Aula 17.

Atualização v0.12.0 (06/11/2026): a vertical slice `registrarmanutencao` atravessa microfrontend, Gateway, BFF, Operações e PostgreSQL. O registro e `ManutencaoRegistrada` v1 são atômicos pela outbox. O publicador escolhe a routing key pelo tipo; Indicadores mantém fila, DLQ e projeção idempotente separadas das de abastecimento. O cadastro não muda automaticamente o status do veículo e não oferece edição ou exclusão, preservando o histórico. Veja a ADR 0017 e a Aula 16.

## Como o sistema se divide

O navegador carrega um **shell** e microfrontends de Frota, Operações e Painel. O **API Gateway** é a entrada das APIs; o **BFF Web** prepara respostas adequadas às telas. Identidade, Frota, Operações e Indicadores são **microsserviços** Java com implantação, credenciais, banco PostgreSQL e migrações Flyway próprios.

Um serviço não consulta tabelas de outro. Quando precisa de uma decisão imediata, usa a API pública do dono do dado; quando precisa apenas reagir a um fato concluído, consome um evento. Assim, registrar um abastecimento não depende de atualizar o painel ou enviar e-mail antes de responder ao usuário.

## Estilos exigidos e evidências futuras

| Estilo | Aplicação no NexFleet | Evidência necessária no código |
|---|---|---|
| Microfrontend | Shell e três áreas de interface. | Implementado na v0.7.0 com builds independentes e contrato `mount/unmount`. |
| API Gateway | Entrada e políticas de borda. | Roteamento e correlação implementados; limites de tráfego pertencem à publicação. |
| BFF | Resposta específica para a interface web. | Composição de APIs sem SQL ou regra de domínio. |
| Microsserviços + Database per Service | Identidade, Frota, Operações e Indicadores. | Deploy, credenciais, Flyway e banco isolados por serviço. |
| EDA | Outbox e broker após commit local. | Evento versionado, consumidor idempotente, retry e DLQ. |
| Serverless | Notificação acionada por evento. | Implementado localmente na v0.14.0 com Azure Function, idempotência, retry e DLQ. |
| Clean Architecture + Vertical Slice | Dentro de cada serviço e do BFF. | Pacotes por caso de uso, domínio independente de framework. |
| Testes de arquitetura | CI backend e frontend. | ArchUnit e regras de importação que falham em violação. |

## A fatia crítica: registrar abastecimento

O MFE chama Gateway e BFF. Operações valida o comando e a referência pública de Frota, grava abastecimento, hodômetro e evento de outbox **na mesma transação local**, e só então responde `201`. Depois do commit, um publicador envia o evento ao broker. Indicadores e a função de notificação o consomem de forma idempotente. Se o broker falhar, a gravação não é desfeita: o evento permanece pendente no outbox. Se a quilometragem regredir, o serviço responde `422` sem gravar nada.

## Organização observada na fatia crítica

```text
operacoes/registrarabastecimento/
├── api/             HTTP, DTO e autorização de entrada
├── application/     comando, caso de uso e portas
└── infrastructure/  JDBC e cliente HTTP de Frota
```

A API chama a aplicação, e a infraestrutura implementa as portas `Abastecimentos` e `ReferenciasFrota` definidas pela aplicação. Esta fatia não possui pacote `domain` nem JPA: as validações de entrada estão em `GerenciarAbastecimentos`, enquanto atomicidade, bloqueio do hodômetro e outbox ficam no adaptador `JdbcAbastecimentos`. Outros domínios possuem tipos próprios, como `StatusVeiculo`, `StatusMotorista` e `Perfil`. Os testes de arquitetura impedem que serviços importem classes internas uns dos outros.

## Situação da implementação

Atualização v0.11.0 (05/11/2026): o consumidor de Indicadores tenta processar cada falha até três vezes, com espera progressiva. Depois do esgotamento, rejeita a mensagem sem recolocá-la na fila principal; o RabbitMQ a encaminha pelo dead-letter exchange para uma DLQ durável. Isso isola mensagens problemáticas e preserva o processamento das seguintes. A fila principal recebe um novo nome porque argumentos de dead-letter não podem ser alterados em uma fila RabbitMQ já existente. Manutenções continuam pendentes. Veja a ADR 0016 e a Aula 15.

Atualização v0.10.0 (05/11/2026): Indicadores passou a consumir `AbastecimentoRegistrado` v1 e gravar sua própria projeção PostgreSQL. A chave primária `evento_id` e `INSERT ... ON CONFLICT DO NOTHING` tornam o consumidor idempotente. A fila e o binding pertencem ao consumidor; Operações detecta publicação sem rota e mantém o evento na outbox para retry. A validação local entregou duas cópias iguais e criou uma única projeção, além de comprovar o fluxo completo Operações → RabbitMQ → Indicadores. Veja a ADR 0015 e a Aula 14.

Atualização v0.9.0 (05/11/2026): a segunda fatia da Sprint 2 conecta a outbox ao RabbitMQ. Um job bloqueia lotes pendentes com `FOR UPDATE SKIP LOCKED`, publica mensagens persistentes e só preenche `publicado_em` depois do `publisher confirm`. Falhas incrementam `tentativas`, guardam erro e agendam retry sem derrubar a API de Operações. Testes reais comprovaram retenção com o broker parado, recuperação automática e persistência da fila após reinício. Consumidores idempotentes, DLQ e manutenção continuam pendentes. Veja a ADR 0014 e a Aula 13.

Atualização v0.8.0 (05/11/2026): a primeira fatia da Sprint 2 registra abastecimentos de ponta a ponta. Operações valida a referência temporal em Frota, serializa atualizações por hodômetro e grava abastecimento, hodômetro e `AbastecimentoRegistrado` v1 na mesma transação. A migração V2 foi aplicada em PostgreSQL real; o fluxo público comprovou `201`, outbox única e `422` para regressão sem segunda gravação. Veja a ADR 0013 e a Aula 12.

Atualização v0.7.0 (28/10/2026): `frontend` é o shell e carrega em runtime os remotos Frota, Operações e Painel. Cada remoto possui `package.json`, lockfile, testes, build Vite e porta próprios. URLs vêm de variáveis `VITE_MFE_*_URL`; o shell não importa código-fonte dos MFEs. Frota contém as capacidades reais da Sprint 1. Operações e Painel são estruturas vazias de negócio até suas sprints, sem respostas simuladas. A ADR 0012 e a Aula 11 registram o contrato e a execução.

Atualização v0.6.0 (23/10/2026): três fatias verticais de Frota percorrem React → Gateway → BFF → Frota → PostgreSQL. Veículos implementa cadastro, consulta, edição, filtro e inativação. Motoristas implementa cadastro, consulta, edição e filtro, com CPF/CNH únicos e mascarados na lista. Vínculos implementa criação, histórico, filtro por veículo e encerramento, com unicidade ativa por veículo no banco. No perfil `jwt-rsa`, BFF e Frota validam independentemente o token pela chave pública JWKS de Identidade; a chave privada continua exclusiva de Identidade. As tabelas entram pelas migrações V2, V3 e V4. Veja as ADRs 0009–0011 e as Aulas 8–10.

Gateway continua responsável pela entrada e pelo roteamento explícito, mas não é a única barreira de segurança: BFF e o serviço dono do dado rejeitam tokens inválidos. Microfrontends independentes estão implementados; a outbox local começou na v0.8.0, o broker entrou na v0.9.0, o primeiro consumidor idempotente na v0.10.0, a DLQ em Indicadores na v0.11.0 e a Function serverless local na v0.14.0. Na v0.29.0, Service Bus e os workloads Azure foram preparados; a implantação e a prova em nuvem permanecem na Sprint 4.

Em 18/10/2026 começou a primeira parte da Sprint 0 em `services/`: seis projetos Java independentes, consulta técnica Gateway → BFF → serviços, portas/adaptadores de disponibilidade, migrações iniciais e regras ArchUnit. `compose.sprint0.yaml` define quatro bancos com redes e credenciais separadas. A consulta usa JDBC sem JPA porque ainda não há entidades persistentes de negócio; JPA entra nas fatias que precisarem de mapeamento de entidades.

O esqueleto anterior em `backend/` foi preservado. Em 19/10/2026 foi adicionada a primeira tela técnica do shell em `frontend/`, consumindo o Gateway pelo proxy local do Vite. Microfrontends independentes, cadastros de negócio, broker, outbox e função serverless continuam planejados. A execução real dos bancos e migrações depende da validação com Docker ativo. Consulte a [Aula 1](tutorials/01-fundamentos.md) e a [Aula 2](tutorials/02-primeira-tela.md). A implantação efetiva na Azure faz parte da Sprint 4; o proxy local não substitui o roteamento HTTPS da publicação.

Na Sprint 1, autenticação BCrypt/JWT foi implementada em `identidade/autenticar`, com portas independentes e adaptadores JDBC/criptografia. A tabela `identidade.usuario` entra por V2, sem alterar bancos de outros serviços. A v0.2.0 conecta o login à interface e às rotas explícitas do Gateway/BFF. BFF delega a validação do Bearer a Identidade: não recebe chave de assinatura e não concede perfis. As ADRs [0004](adr/0004-autenticacao-local-inicial.md) e [0005](adr/0005-login-web-com-validacao-delegada.md) registram o escopo local e as limitações.
