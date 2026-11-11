# Histórico de entregas

## v0.30.0 — 11/11/2026

- **Novo — botão Excluir** nas telas de Veículos, Motoristas e Usuários (ADR 0038).
  - Aparece somente em registros inativos e pede confirmação.
  - Só exclui o que **não tem histórico**:
    - veículo sem vínculos e sem manutenções;
    - motorista sem vínculos;
    - usuário desativado e diferente do próprio Administrador.
  - Com histórico, a mensagem orienta a mantê-lo inativo. Isso preserva o CQ05.
  - Novas rotas `DELETE /api/v1/{veiculos|motoristas|usuarios}/{id}/definitivo`, com os contratos OpenAPI atualizados.
  - As rotas foram incluídas nas listas explícitas de rotas permitidas do Gateway, do BFF e da Identidade, só com o método `DELETE`. Um teste HTTP no Gateway e outro na Identidade cobrem isso.
- **Homologação:** os dados criados pelos testes automáticos (veículos `HML...`, motoristas, vínculos, abastecimentos, projeções do painel e e-mails capturados) foram removidos. O ambiente ficou pronto para uso.

## Ajustes pós-homologação — 11/11/2026

- **Correção:** os microfrontends publicados (Frota, Operações e Painel) não carregavam no navegador; aparecia "Não foi possível carregar…".
  - **Causa:** no modo biblioteca, o Vite não substitui `process.env.NODE_ENV`, e o React o lê ao ser carregado. O resultado era `process is not defined`.
  - **Correção:** `define` em cada `vite.config.ts`. O pacote também caiu de cerca de 860 KB para cerca de 310 KB, porque passou a usar o React de produção.
  - **Validação:** login e Painel abertos num navegador automático contra a Azure. O ambiente local (`npm run dev`) não era afetado.
- **Novo:** `Invoke-AzureDatabaseQuery.ps1 -PermitirEscrita`, com confirmação explícita.
- **Novo:** guia `docs/GUIA-ADMINISTRACAO-AZURE.md`, com contas, senhas e escala dos serviços.

## Homologação Azure — 10/11/2026

- **Publicação:** homologação publicada em Central US.
  - Frontend: https://white-mushroom-0cadda010.3.azurestaticapps.net
  - API: https://apim-nexfleet-homolog-ukzjodf42myfe.azure-api.net
  - Seis Container Apps, a Function no Flex Consumption, o PostgreSQL privado, o Service Bus e o ACS Email.
- **Fluxo validado por HTTPS** (`quality/azure/homolog.mjs`): CQ01, login, perfil, cadastro de Gestor, veículo, motorista, vínculo, abastecimento, CQ03, histórico, painel atualizado por evento e e-mail enviado pela Function. As DLQs ficaram vazias.
- **CQ09:** aprovado na região, com p95 de 900 ms e 0 falhas em 1.800 requisições no perfil carga. As medições pela rede doméstica (p95 de 2,6 a 2,8 s) estão documentadas.
- **CQ10:** aprovado por restauração point-in-time em servidor temporário. RPO de 1,1 min, RTO de 8,9 min, 0 divergências.
- **Novos scripts e componentes:**
  - `Publish-AzureImages.ps1`, `Publish-AzureDatabaseMigration.ps1`, `Publish-AzureFunction.ps1`, `Publish-AzureFrontend.ps1`, `Test-AzureHomologation.ps1` e `Test-AzureRecovery.ps1`.
  - O pacote Azure da Function leva somente o gatilho Service Bus, o que eliminou o erro de indexação do gatilho RabbitMQ.
  - Jobs de banco em `migration-job.bicep`, com `verify.sh` e `bootstrap-admin.sh`.
  - Perfil `workloadProfile` (`economico`/`carga`).
- **Correções vindas da nuvem:**
  - GUID do papel Service Bus Data Receiver.
  - Concorrência na API do APIM.
  - Regras das assinaturas Service Bus: `$Default` não persistia e os eventos eram descartados.
  - Pacote zip da Function com barras invertidas.
  - Scripts robustos aos resets TLS do Windows PowerShell 5.1.
- **E-mail:** Azure Communication Services Email autorizado (ADR 0036), com domínio gerenciado e identidade gerenciada. O Bicep agora tem 22/22 tipos.

## 0.29.0 — 09/11/2026

- Operações publica a outbox por RabbitMQ no ambiente local ou por Azure Service Bus na nuvem, selecionado por `MESSAGING_PROVIDER` e autenticado por identidade gerenciada.
- Indicadores recebeu processador Service Bus com as mesmas garantias de idempotência do consumidor RabbitMQ; testes específicos protegem publicação, propriedades, correlação e despacho dos dois tipos de evento.
- A Azure Function possui gatilhos separados para RabbitMQ e Service Bus. O gatilho Service Bus fica desativado localmente e o RabbitMQ continua validado no Compose.
- Azure Communication Services Email foi implementado como adaptador opcional. `captured-local` permanece o padrão seguro e nenhum e-mail real foi enviado.
- A migração V2 de Notificações registra destinatário, provedor, identificador externo, estado de entrega e erro, preservando auditoria e idempotência.
- Bicep evoluiu para 19/19 tipos modelados: rede virtual, DNS privado, PostgreSQL privado, seis Container Apps, uma identidade por workload, ACR Pull e papéis mínimos de Service Bus.
- O frontend ganhou URL de API configurável e empacotamento para Static Web Apps com shell, três microfrontends, CSP e fallback de navegação.
- A tentativa de executar Flyway no cold start da Function foi removida após prova integrada; as migrações continuam como etapa anterior e independente do consumidor.
- Verificação final: 176 testes dos seis serviços, 8 testes da Function, 47 testes frontend, quatro builds Vite, Bicep com 19 tipos/0 pendências e fluxos EDA/serverless locais aprovados.
- Nenhum workload pago foi implantado. `what-if`, credenciais PostgreSQL por serviço, provedor de e-mail, publicação HTTPS e repetição de CQ09/CQ10 em homologação continuam como barreiras explícitas.

## 0.28.0 — 08/11/2026

- Os cinco registros de provedores autorizados foram concluídos e verificados: API Management, Container Registry, PostgreSQL, Key Vault e Managed Identity.
- `Register-AzureProviders.ps1` torna o procedimento explícito, idempotente, tolerante a falhas transitórias e limitado à lista autorizada.
- Orçamento mensal de R$ 100 foi configurado no Cost Management para o grupo planejado de homologação, com alertas em 50% real, 80% real e 100% previsto.
- `Set-AzureBudget.ps1` reproduz o orçamento a partir do perfil local sem publicar workloads; o orçamento alerta, mas não desliga recursos.
- `Brazil South` permanece como região de backend/dados e `East US 2` como região do Static Web Apps; Service Bus foi aprovado como mensageria de nuvem.
- Backup PostgreSQL por sete dias foi aprovado. Azure Communication Services Email foi recomendado, mas seu provedor e recurso não foram registrados/criados sem nova autorização.
- Guia de execução no macOS, ADR 0033, Aula 32 e relatório da entrega explicam decisões, execução e pendências.
- Nenhum grupo, banco, barramento, contêiner, Function, API Management ou outro workload pago foi implantado.

## 0.27.0 — 08/11/2026

- Azure CLI autenticado na assinatura estudantil e descoberta conectada executada sem criar ou alterar recursos.
- `Get-AzureReadiness.ps1` separa descoberta somente leitura das oito aprovações humanas do preflight e grava relatório local ignorado pelo Git.
- A consulta real conferiu 16 tipos: `Brazil South` suporta 15; Static Web Apps exige região de metadados separada.
- O perfil Azure evolui para v3 com `staticWebLocation`; o Bicep mantém backend e dados na região principal e aceita o frontend em `East US 2` como candidato explícito.
- O invocador compartilhado encontra o Azure CLI mesmo quando o processo ainda não recebeu o novo `PATH`, repete falhas transitórias e oculta UUIDs em erros.
- Preflight deixa de usar `az account list-locations --subscription`, combinação incompatível com a CLI instalada, e reduz as consultas de provedores a uma leitura consolidada.
- Cinco provedores necessários foram identificados como `NotRegistered`; o projeto não os registra automaticamente e continua sem script de implantação.
- Descoberta offline, perfil v3 e Bicep atualizado passam na suíte local e na configuração de CI.

## 0.26.0 — 08/11/2026

- Infraestrutura Azure ganha Bicep de assinatura e plataforma, compilado offline sem acessar conta ou criar recurso.
- Orçamento, monitoramento, ACR, Key Vault, Storage, Service Bus, PostgreSQL 18, Container Apps Environment, Static Web App, APIM, Function Flex, identidade e RBAC estão modelados.
- `publicationApproved=false`, plano sem autorização e ausência de script de deploy protegem contra criação acidental.
- Perfil de preflight v2 aceita assinatura paga ou estudantil e moeda de cobrança configurável.
- Inventário cresce para 16 tipos; 15 estão no Bicep e Container Apps permanece pendente até a migração Service Bus.
- Lint/build Bicep entram na suíte local e CI com versão/checksum fixos.
- `Invoke-AzureWhatIf.ps1` executa somente preflight + `what-if`, reprova exclusões e remove parâmetros temporários.
- ADR 0031, Aula 30, guia Bicep e entrega v0.26.0 registram limites e próximos passos.

## 0.25.0 — 08/11/2026

- Pré-publicação Azure protegida por perfil local, schema e oito aprovações humanas obrigatórias.
- Inventário versionado cobre 12 tipos de recurso da arquitetura-alvo e não presume região ou SKU.
- `Test-AzurePreflight.ps1` valida o modelo na CI e, quando configurado, consulta assinatura, regiões e provedores sem alterar a Azure.
- Perfil incompleto reprova antes de procurar o Azure CLI; o exemplo não contém assinatura, orçamento ou autorização reais.
- `Test-Project.ps1` e o workflow backend passam a validar a barreira de publicação.
- ADR 0030, Aula 29, guia Azure e entrega v0.25.0 documentam instalação, decisões e limites.

## 0.24.0 — 08/11/2026

- C4 níveis 1–4, UML de componentes/classes/sequências e DER revisados contra a implementação atual.
- Novo documento Mermaid versionável separa os cinco bancos físicos e inventaria as onze tabelas de negócio.
- Relações por UUID entre serviços são descritas como referências lógicas sem FK cruzada.
- A visão de Registrar Abastecimento passa a refletir JDBC e os pacotes reais `api/application/infrastructure`, sem declarar JPA ou `domain` inexistentes na fatia.
- O módulo `quality` confronta os diagramas com todas as migrações e 17 classes centrais; 4 testes foram aprovados.
- ADR 0029, Aula 28 e entrega v0.24.0 documentam a manutenção dos diagramas junto ao código.

## 0.23.0 — 08/11/2026

- CQ07 aprovado com o JAR real de Frota e PostgreSQL temporário em rede Docker exclusiva.
- Readiness comprovado como `UP/200` antes da falha e `DOWN/503` depois da parada controlada do banco efêmero.
- A API técnica devolve `DOWN/503` e preserva o `X-Correlation-ID` observado no log.
- Senha de banco e token Bearer sentinelas não aparecem nos logs capturados.
- `Test-Cq07.ps1`, `Test-Project.ps1 -IncludeDatabaseIntegration` e o workflow backend automatizam a regressão.
- ADR 0028, Aula 27, evidência CQ07 e entrega v0.23.0 documentam a estratégia e o resultado.

## 0.22.0 — 08/11/2026

- CQ05 aprovado em dois PostgreSQL efêmeros e separados, preservando a fronteira entre Frota e Operações.
- A prova cria o veículo ativo, registra um abastecimento, inativa o cadastro e consulta novamente o histórico pela camada HTTP.
- A resposta final preserva `realizadoEm`, `motoristaId` e `criadoEm`; o veículo permanece cadastrado com status `INATIVO`.
- `Test-Cq05.ps1` orquestra quatro fases com identificadores compartilhados, portas e credenciais temporários.
- `Test-Project.ps1 -IncludeDatabaseIntegration` e o workflow backend passam a executar CQ03, CQ04 e CQ05.
- ADR 0027, Aula 26, evidência CQ05 e entrega v0.22.0 documentam a estratégia e o resultado.

## 0.21.0 — 08/11/2026

- CQ03 aprovado em PostgreSQL real efêmero: tentativa de 999 km com hodômetro em 1000 retorna `422`, não grava abastecimento/outbox e preserva o hodômetro.
- CQ04 aprovado com falha controlada na outbox depois das escritas anteriores; abastecimento, hodômetro e evento sofrem rollback integral.
- `Test-Cq03Cq04.ps1` cria porta e credenciais aleatórias, aplica Flyway V1–V5 e remove o contêiner sem tocar nos bancos ativos.
- `Test-Project.ps1 -IncludeDatabaseIntegration` inclui a nova prova na suíte geral.
- Workflow backend passa a executar os dois testes integrados em toda mudança pertinente.
- ADR 0026, Aula 25, evidência CQ03/CQ04 e entrega v0.21.0 documentam a estratégia e o resultado.

## 0.20.0 — 08/11/2026

- CQ06 formalizado nos sete formulários críticos: login, usuários, veículos, motoristas, vínculos, abastecimentos e manutenções.
- O feedback preserva valores válidos, marca controles incorretos com estado visual e `aria-invalid`/`aria-describedby` e apresenta orientação com `role="alert"`.
- Quatro testes de aceitação protegem os fluxos representativos do shell, gestão de usuários, Frota e Operações.
- A matriz CQ01–CQ12 distingue cenários aprovados, aprovados localmente com repetição pendente e provas integradas ainda abertas.
- O módulo `quality` verifica que a matriz mantém exatamente CQ01–CQ12 em ordem.
- Verificação local: 3 testes de qualidade, 172 testes dos serviços Java, 8 testes da Function, 47 testes frontend e quatro builds Vite aprovados.
- ADR 0025, Aula 24, evidência CQ06 e entrega v0.20.0 documentam o comportamento e os limites.

## 0.19.0 — 08/11/2026

- CQ10 automatizado para os cinco bancos PostgreSQL, com RPO máximo de 24 horas e RTO máximo de 4 horas.
- `Backup-Databases.ps1` gera dumps customizados, inventário de tabelas/linhas, tamanhos e hashes SHA-256 sem parar o ambiente.
- `Test-Recovery.ps1` restaura em PostgreSQL 18 temporários sem portas ou rede, compara as 16 tabelas e remove todos os artefatos de ensaio.
- A pasta `backups/` foi excluída do Git; a documentação alerta que cópias preservadas contêm dados e exigem criptografia e acesso restrito.
- `Test-E2E.ps1 -IncludeRecovery` e a CI efêmera passam a repetir a prova de recuperação.
- Prova local integrada: cinco bancos restaurados sem divergências, RPO observado de 0,25 minuto e RTO conjunto de 0,72 minuto.
- ADR 0024, Aula 23 e evidência CQ10 registram o procedimento e os limites para produção/Azure.

## 0.18.0 — 07/11/2026

- CQ09 automatizado com 100 usuários virtuais concorrentes sobre as seis listas paginadas, sem gravar dados.
- O executor calcula p50, p95, p99, máximo, vazão e falhas no total e por endpoint; qualquer erro ou p95 maior ou igual a 2 segundos reprova o ensaio.
- `Test-Performance.ps1` utiliza a configuração local sem imprimir credenciais e restaura as variáveis temporárias ao terminar.
- `Test-E2E.ps1 -IncludePerformance` inclui a prova na suíte integrada; a CI efêmera executa esse modo com Node.js 24.
- Prova E2E local: 1.800 requisições, nenhuma falha, p95 geral de 974,59 ms e maior p95 individual de 1.004,27 ms.
- ADR 0023, Aula 22 e evidência CQ09 registram método, resultado e necessidade de repetição na homologação Azure.

## 0.17.0 — 07/11/2026

- Dez contratos OpenAPI cobrem todas as rotas web; abastecimentos recebeu contrato próprio e manutenções passou a descrever respostas completas.
- `eventos.asyncapi.yaml` documenta `AbastecimentoRegistrado.v1` e `ManutencaoRegistrada.v1`, incluindo routing keys, cabeçalhos, versão, correlação e payloads.
- Módulo independente `quality` valida YAML sem chaves duplicadas, referências locais, `operationId`, segurança, parâmetros, respostas 2xx e inventário de rotas públicas.
- `Test-ApiContracts.ps1` comprova no Compose login, sessão, autorização, Frota, Operações, Dashboard e correlação sem gravar dados de negócio.
- `Test-E2E.ps1` agrega saúde, contratos HTTP, consumidores/DLQs, Function idempotente e seis alvos Prometheus.
- O teste serverless agora publica evento conforme o contrato atual, com propriedades RabbitMQ e `X-Correlation-ID`, preservando a prova de compatibilidade antiga nos testes unitários.
- Workflows passam a validar contratos em toda mudança pertinente e possuem ambiente E2E efêmero, removido com volumes ao final da execução remota.
- Verificação local: 2 testes de contrato, 172 testes dos serviços Java, 8 da Function, 43 dos frontends, quatro builds Vite e E2E integrado aprovados.

## 0.16.0 — 07/11/2026

- `X-Correlation-ID` validado como UUID no Gateway, devolvido uma única vez na resposta e propagado pelo BFF e por Operações nas chamadas HTTP internas.
- Logs uniformes nos seis serviços Java com `service`, `correlationId`, método, caminho, status e duração, sem corpo, query string, JWT, CPF, CNH ou senha.
- Migração V5 acrescenta `correlation_id` obrigatório à outbox; eventos novos levam a correlação no payload JSON e no cabeçalho RabbitMQ.
- Indicadores preserva a correlação ao consumir abastecimentos e manutenções; a Azure Function registra apenas metadados seguros e aceita eventos antigos usando `eventoId` como fallback.
- ADR 0021, Aula 20 e documentação da entrega explicam a rastreabilidade ponta a ponta e como investigá-la localmente.
- Verificação local: 172 testes dos serviços Java, 8 testes da Function, 43 testes frontend e quatro builds Vite aprovados.
- Prova integrada no Compose: o mesmo UUID foi observado em Gateway, BFF, Identidade, Frota, Operações e Indicadores; Flyway V5 aplicada no PostgreSQL real e todos os contêineres permaneceram saudáveis.

## 0.15.0 — 07/11/2026

- Sprint 4 iniciada com métricas Prometheus nos seis processos Java: Gateway, BFF, Identidade, Frota, Operações e Indicadores.
- Micrometer identifica cada série pelo nome da aplicação. BFF e serviços expõem `/actuator/prometheus` apenas na rede interna do Compose; o Gateway expõe somente as próprias métricas na porta ligada ao loopback e não encaminha métricas dos serviços.
- Prometheus LTS coleta os alvos a cada 15 segundos, mantém sete dias de dados locais e fica disponível somente em `127.0.0.1:9090`.
- A subida local agora valida pela API do Prometheus que todos os seis alvos estão `UP`.
- Instalador reprodutível baixa Node.js 24 e JDK 21 portáteis com checksum, instala os quatro conjuntos npm e prepara o cache Maven.
- Estado das sprints, pendências de qualidade e roteiro de execução consolidados em `docs/STATUS-SPRINTS.md`.
- Verificação local: 165 testes dos serviços Java, 6 testes da Function, 43 testes frontend e quatro builds Vite aprovados.
- Limite desta máquina: Docker Desktop e WSL 2 não estão instalados; por isso a nova coleta Prometheus foi validada por build/configuração, mas ainda precisa da prova integrada em contêineres.

## 0.14.0 — 06/11/2026

- Sprint 3 concluída localmente com Azure Function Java 21 acionada por `AbastecimentoRegistrado.v1` no RabbitMQ.
- Clean Architecture e Vertical Slice aplicadas em `notificarabastecimento`, com seis testes unitários/ArchUnit.
- Idempotência por `evento_id`: duas entregas do mesmo evento produzem um único registro auditável.
- Fila quorum com limite de três entregas, dead-letter exchange e DLQ exclusiva de notificações.
- Flyway separado da execução serverless e executado antes da Function, evitando migração no cold start.
- Azurite fornece o `AzureWebJobsStorage` apenas no ambiente Docker local.
- O adaptador local captura a solicitação de e-mail; destinatário e provedor externo permanecem decisão da Sprint 4.
- Teste integrado comprova consumo, duplicata e encaminhamento de mensagem inválida à DLQ.

## 0.13.0 — 06/11/2026

- RF14/RB15/RB16: dashboard com gastos válidos, situação da frota e próximas manutenções.
- Custos calculados no banco próprio de Indicadores a partir das projeções idempotentes.
- BFF compõe contratos de Indicadores e Frota sem SQL cruzado ou banco compartilhado.
- Indicadores protegido por JWT RSA/JWKS para Administrador e Gestor de Frota.
- Rota pública explícita no Gateway e interface real no microfrontend Painel.
- Primeira fatia da Sprint 3 concluída; função serverless e Azure permanecem pendentes.

## 0.12.0 — 06/11/2026

- RF12–13: registro e histórico paginado de manutenções, com filtro por veículo.
- Tipos previstos no PJBL, data, quilometragem, descrição, oficina, valor e próxima manutenção.
- RB05/RB13: veículo inexistente ou inativo é recusado; próxima data deve ser posterior.
- Registro e `ManutencaoRegistrada` v1 gravados juntos pela outbox transacional.
- Rota, fila, consumidor idempotente, projeção PostgreSQL e DLQ exclusivos de manutenção.
- Interface completa no microfrontend Operações por Gateway e BFF.
- Sprint 2 concluída localmente, sem antecipar dashboard, serverless ou Azure.

## 0.7.0 — 28/10/2026

- Shell e três microfrontends React/TypeScript/Vite com builds e portas independentes.
- Frota extraída do shell sem alterar as APIs de veículos, motoristas e vínculos.
- Operações e Painel entregues como estruturas independentes, sem dados simulados antes das Sprints 2 e 3.
- Contrato de runtime `mount/unmount`, URLs configuráveis e tratamento de remoto indisponível.
- Migração V4 e fluxo completo de vínculos comprovados com PostgreSQL 18 e Java 21 no Docker.
- Corrigido o perfil padrão RSA do Compose para não ativar `local-seed` sem credenciais.
- 135 testes backend no build Docker e 42 testes frontend distribuídos entre shell e MFEs.

## 0.6.0 — 23/10/2026

- RF08 e RB05–07: criação, consulta e encerramento de vínculos históricos.
- Veículo inativo, motorista inativo e CNH vencida são recusados em novos vínculos.
- Migração aditiva V4 com chaves locais, auditoria e índice único parcial por veículo ativo.
- Interface integrada ao Gateway, BFF e serviço Frota, com histórico filtrável por veículo.
- Horários de início/fim definidos pelo servidor; encerramento preserva a linha.
- Contrato OpenAPI, ADR 0011, Aula 10 e testes de domínio/HTTP/encaminhamento/interface.
- Não foi criada restrição inversa por motorista porque ela não consta no PJBL.

## 0.5.0 — 23/10/2026

- Cadastro, consulta paginada, filtro e edição de motoristas pela interface completa.
- RF06/RF07 e RB04: CPF e CNH normalizados, com unicidade protegida pelo PostgreSQL.
- Migração aditiva V3 no banco Frota, sem alterar ou remover veículos existentes.
- JWT RSA validado no BFF e em Frota; dados acessíveis somente à equipe de Frota.
- CPF e CNH mascarados na listagem e ausentes de logs da aplicação.
- Contrato OpenAPI, testes de regra/HTTP/encaminhamento/interface, ADR 0010 e Aula 9.
- Vínculos históricos continuam pendentes até fechar as decisões de RB06/RB07.

## 0.4.0 — 23/10/2026

- BFF verifica RS256/JWKS no perfil RSA; preserva delegação posterior de sessão.
- Gestão administrativa de usuários pela interface, Gateway, BFF e Identidade.
- Migração aditiva V3: perfis Administrador/Gestor, sem promoção automática de contas.
- JWT com perfil; autorização administrativa e verificação do estado atual da conta.
- Cadastro, consulta paginada, edição e desativação lógica, com DTOs sem credenciais.
- Primeira fatia vertical de Frota: cadastro, consulta, edição, filtro e inativação de veículos.
- Placa única, migração Flyway V2, auditoria por UUID e validação JWT no próprio serviço Frota.
- Contrato OpenAPI, testes de regra/arquitetura/encaminhamento e Aula 8.
- Sem novo ZIP parcial; o histórico continua em uma única base integrada.

## 0.3.0 — 20/10/2026

- Perfil opcional `jwt-rsa`: chave privada externa PKCS#8, assinatura RS256 e `kid`.
- Endpoint interno JWKS contém somente a chave pública; nenhum segredo compartilhado.
- Gerador local recusa sobrescrita; override Compose monta a chave apenas em Identidade.
- Modo HS256 anterior preservado, sem alteração de schema ou contrato de login.
- Aula 5 e ADR 0006 explicam ativação, novo login obrigatório na troca e rollback.
- Validação distribuída, permissões, cadastros e banco real continuam pendentes.

## 0.2.0 — 20/10/2026

- Login e consulta de sessão na interface, acessando somente Gateway/BFF.
- Rotas explícitas de autenticação, delegação da validação a Identidade e respostas sem cache.
- Sessão em memória, saída local e expiração automática, sem persistir tokens.
- Testes de interação, clientes HTTP, regras de aplicação e roteamento.
- Sem alteração de schema, chaves de assinatura ou credenciais existentes.
- Continua sem cadastros, perfis, validação com bancos reais e conclusão das sprints.

## 0.1.0 — 19/10/2026

Primeira entrega organizada e versionada em Git. Não é a conclusão da Sprint 1.

- Separação do código ativo do esqueleto antigo e dos arquivos temporários.
- Importação da implementação existente sem alterações funcionais.
- Formatação consistente de Java, POMs e frontend.
- Maven Wrapper 3.3.4, Maven 3.9.16 e comando central de verificação.
- Workspace VS Code, README de entrada e gate explícito antes da Sprint 2.
- Histórico local iniciado nesta entrega; sem publicação em repositório remoto.

Limitações preservadas: login apenas interno, cadastros/perfis/microfrontends pendentes e ausência de validação ponta a ponta com PostgreSQL real.
