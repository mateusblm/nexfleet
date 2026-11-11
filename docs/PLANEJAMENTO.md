# NexFleet — implementação por sprints

Uma **sprint** é um período curto que termina com algo demonstrável. O [PJBL enviado pelo usuário](reference/ArqCloud_PJBL-Completo.pdf) define a arquitetura-alvo; nenhum estilo é considerado implementado só por aparecer no PDF. O pedido atual é uma entrega única integrada, seguindo [ESCOPO-PJBL](ESCOPO-PJBL.md). As etapas abaixo são histórico de implementação, não produtos separados. Em cada etapa, explicaremos **o que é, por que usar, como construir e quando usar** antes de codificar.

| Sprint | O que será construído e por quê | Como comprovar a conclusão |
|---|---|---|
| 0 — Fundamentos | Contratos iniciais, estrutura de shell/MFEs, Gateway, BFF, serviços, bancos isolados, Compose e CI. Fronteiras claras evitam acoplamento desde o começo. | Ambiente local sobe; health checks e primeira regra ArchUnit passam. |
| 1 — Identidade e Frota | JWT/BCrypt, usuários, veículos, motoristas, vínculos e MFEs básicos. As operações precisam de identidade e referências confiáveis. | Login, `401/403`, unicidade, regras de cadastro e autorização testados. |
| 2 — Operações e EDA | Abastecimento, hodômetro, manutenção, outbox e broker. A transação local protege o registro; eventos desacoplam painel e avisos. | Rollback, quilometragem não regressiva, retry, duplicata e idempotência demonstrados. |
| 3 — Leitura e serverless | Indicadores, dashboard e função de notificação. A leitura usa projeções; e-mail não bloqueia o comando. | Projeções são atualizadas por eventos; função tolera repetição e falhas vão para DLQ. |
| 4 — Qualidade e publicação Azure | Contratos, testes ponta a ponta, observabilidade, revisão de C4/UML/DER e implantação na Azure. | Aplicação acessível por HTTPS; fluxos essenciais validados na nuvem; custos, segurança, backup e segredos revisados. Recursos pagos dependem da confirmação da conta, região e orçamento. |

## Critério comum de cada sprint

### Trabalho integrado atual — Sprint 4 em andamento

A v0.15.0 inicia a qualidade operacional com Micrometer e Prometheus nos seis serviços Java. O Compose coleta métricas internamente, mantém sete dias de histórico local e o `Start-Local.ps1` confirma os seis alvos pela API do Prometheus. A decisão está na [ADR 0020](adr/0020-observabilidade-prometheus-local.md) e a explicação na [Aula 19](tutorials/19-observabilidade.md).

A v0.16.0 acrescenta `X-Correlation-ID` validado no Gateway, propagação HTTP, persistência na outbox, cabeçalho RabbitMQ e restauração do contexto em Indicadores e na Function. Logs seguros dos seis serviços agora podem ser pesquisados pelo mesmo UUID. A decisão está na [ADR 0021](adr/0021-correlacao-ponta-a-ponta.md) e a prática na [Aula 20](tutorials/20-correlacao-ponta-a-ponta.md).

A v0.17.0 transforma os contratos em verificações executáveis. Dez OpenAPI e um AsyncAPI passam por regras estruturais independentes, enquanto `Test-E2E.ps1` comprova login, autorização, consultas das fatias críticas, mensageria, Function e métricas no Compose. A decisão está na [ADR 0022](adr/0022-contratos-executaveis-e-smoke-e2e.md), e a prática na [Aula 21](tutorials/21-contratos-e-smoke-e2e.md).

A v0.18.0 automatiza CQ09 com 100 usuários virtuais e reprovação por p95 total ou individual. A prova E2E local realizou 1.800 consultas sem falhas e obteve p95 geral de 974,59 ms. A decisão está na [ADR 0023](adr/0023-teste-de-desempenho-cq09.md), a prática na [Aula 22](tutorials/22-teste-de-desempenho-cq09.md) e os números na [Evidência CQ09](EVIDENCIA-CQ09-DESEMPENHO.md).

A v0.19.0 automatiza CQ10: cinco dumps recebem manifesto e SHA-256, são restaurados em PostgreSQL temporários e têm 16 tabelas comparadas. A prova local mais recente observou RPO de 0,25 minuto e RTO de 0,72 minuto. Veja a [ADR 0024](adr/0024-backup-e-recuperacao-cq10.md), a [Aula 23](tutorials/23-backup-e-recuperacao-cq10.md) e a [Evidência CQ10](EVIDENCIA-CQ10-RECUPERACAO.md).

A v0.20.0 formaliza CQ06 nos sete formulários críticos e cria a [matriz CQ01–CQ12](MATRIZ-CQ01-CQ12.md). Quatro novos testes comprovam preservação de valores válidos, identificação semântica dos campos incorretos e mensagem compreensível. Veja a [ADR 0025](adr/0025-validacao-acessivel-cq06.md), a [Aula 24](tutorials/24-validacao-acessivel-cq06.md) e a [Evidência CQ06](EVIDENCIA-CQ06-USABILIDADE.md).

A v0.21.0 comprova CQ03 e CQ04 em PostgreSQL temporário. A quilometragem regressiva resulta em `422` sem alterar as três tabelas; uma falha controlada na outbox desfaz também as escritas anteriores. Veja a [ADR 0026](adr/0026-postgresql-efemero-cq03-cq04.md), a [Aula 25](tutorials/25-transacoes-postgresql-cq03-cq04.md) e a [Evidência CQ03/CQ04](EVIDENCIA-CQ03-CQ04-TRANSACAO.md).

A v0.22.0 comprova CQ05 em dois PostgreSQL temporários. O ensaio cria o veículo em Frota, registra um abastecimento em Operações, inativa o cadastro e confirma pela API que data e motorista permanecem no histórico. Veja a [ADR 0027](adr/0027-historico-interservicos-cq05.md), a [Aula 26](tutorials/26-historico-apos-inativacao-cq05.md) e a [Evidência CQ05](EVIDENCIA-CQ05-HISTORICO.md).

A v0.23.0 comprova CQ07 com Frota e PostgreSQL temporários. A parada do banco altera readiness e API técnica para `DOWN/503`; o UUID de correlação aparece na resposta e no log, enquanto senha e token sentinelas permanecem ausentes. Veja a [ADR 0028](adr/0028-falha-isolada-e-log-seguro-cq07.md), a [Aula 27](tutorials/27-readiness-e-logs-seguros-cq07.md) e a [Evidência CQ07](EVIDENCIA-CQ07-INDISPONIBILIDADE.md).

A v0.24.0 conclui a revisão de C4 níveis 1–4, UML e DER. Os [diagramas correntes](DIAGRAMAS-ARQUITETURA.md) refletem as classes, rotas e onze tabelas atuais; o módulo `quality` confronta o inventário DER com as migrações e exige as classes centrais do fluxo. Veja a [ADR 0029](adr/0029-diagramas-versionados-e-verificados.md) e a [Aula 28](tutorials/28-diagramas-que-acompanham-o-codigo.md).

A v0.25.0 introduz um [preflight Azure somente de leitura](GUIA-PRE-PUBLICACAO-AZURE.md). O perfil exige orçamento, alertas, cotas, backup, região, escopo de cobrança e decisão do provedor antes de consultar os tipos de recurso. A CI valida somente o exemplo sem dados reais. Veja a [ADR 0030](adr/0030-preflight-azure-somente-leitura.md) e a [Aula 29](tutorials/29-preflight-azure-sem-criar-recursos.md).

A v0.26.0 adiciona [infraestrutura Bicep](GUIA-INFRAESTRUTURA-AZURE-BICEP.md) compilável e bloqueada por padrão. Quinze de 16 tipos estão modelados, o perfil passa a aceitar assinatura paga ou estudantil e `Invoke-AzureWhatIf.ps1` só prevê mudanças. Container Apps aguarda a migração Service Bus. Veja a [ADR 0031](adr/0031-bicep-com-what-if-e-trava-de-publicacao.md) e a [Aula 30](tutorials/30-bicep-e-what-if-sem-implantar.md).

A v0.27.0 adiciona descoberta Azure conectada sem aprovações fictícias. A conta estudantil foi autenticada e 16 tipos foram consultados sem mutação: `Brazil South` atende 15, Static Web Apps exige região própria e cinco provedores ainda não estão registrados. O perfil v3 e o Bicep agora separam a região principal de `staticWebLocation`. Veja a [ADR 0032](adr/0032-descoberta-azure-e-regioes-separadas.md) e a [Aula 31](tutorials/31-descoberta-azure-conectada.md).

A v0.28.0 executa somente as mutações autorizadas: registra cinco provedores e configura orçamento de R$ 100/mês com alertas. Regiões, Service Bus e backup de sete dias foram registrados como decisões. Azure Communication Services Email é a recomendação, mas ainda não foi autorizado/configurado. Veja a [ADR 0033](adr/0033-provedores-orcamento-e-email-azure.md) e a [Aula 32](tutorials/32-provedores-orcamento-e-proximos-passos.md).

A v0.29.0 conclui a preparação técnica dos workloads: adaptadores Service Bus em Operações/Indicadores/Function, e-mail Azure opcional, rede privada, seis Container Apps, identidades/RBAC e pacote frontend. O Bicep compilava com 19/19 tipos e, com o ACS Email, passou a 22/22. A publicação e a validação da homologação foram concluídas em 10/11/2026 (ADR 0037), o que encerra a Sprint 4. Veja a [ADR 0034](adr/0034-transporte-duplo-e-workloads-azure.md), a [Aula 33](tutorials/33-transporte-duplo-e-workloads-azure.md) e a [Entrega v0.29.0](ENTREGA-v0.29.0.md).

Essas fatias concluem a preparação local, não a publicação da Sprint 4. Os doze cenários possuem evidência local, mas CQ09/CQ10 exigem repetição na homologação. Também faltam revisar custo/cotas, criar credenciais PostgreSQL por serviço, executar migrações e `what-if`, aprovar workloads/e-mail e publicar por HTTPS. A situação consolidada está em [STATUS-SPRINTS](STATUS-SPRINTS.md).

### Trabalho integrado atual — Sprint 3 concluída localmente

A v0.13.0 implementou RF14, RB15 e RB16 no dashboard. A v0.14.0 conclui a Sprint 3 com a Azure Function `NotificarAbastecimento`: ela consome eventos depois do commit, registra a solicitação uma única vez por `eventoId` e deixa mensagens inválidas seguirem para uma DLQ após três entregas. Flyway é uma etapa anterior à Function, e o Azurite atende o runtime local. Veja a [ADR 0019](adr/0019-funcao-serverless-de-notificacao.md) e a [Aula 18](tutorials/18-funcao-serverless.md). Envio externo e publicação Azure pertencem à Sprint 4.

### Trabalho integrado atual — vínculos históricos

RF08 e RB05–07 foram implementados como fatia vertical: React → Gateway → BFF → Frota → migração V4. Novos vínculos exigem veículo não inativo, motorista ativo e CNH válida. O banco limita um vínculo ativo por veículo e preserva todas as linhas encerradas. A [ADR 0011](adr/0011-vinculos-historicos.md) fecha a política mínima sem criar a restrição inversa por motorista. Em 28/10/2026, V4, duplicidade concorrente, encerramento e histórico foram comprovados no PostgreSQL real.

### Trabalho integrado atual — microfrontends

A v0.7.0 separa shell, Frota, Operações e Painel em quatro builds React/TypeScript/Vite. O shell carrega cada remoto por URL e passa apenas token/perfil pelo contrato `mount/unmount`. Frota contém as telas existentes; Operações e Painel aguardam suas sprints sem simular dados. Veja a [ADR 0012](adr/0012-contrato-de-microfrontends.md) e a [Aula 11](tutorials/11-microfrontends.md). Com os testes integrados, a base funcional da Sprint 1 está concluída localmente.

### Trabalho integrado atual — cadastro de motoristas

RF06, RF07 e RB04 foram implementados como fatia vertical: React → Gateway → BFF → Frota → migração V3. CPF e CNH são normalizados, únicos e mascarados na listagem. O cadastro aceita CNH vencida para preservar histórico; a criação de vínculo aplica a validade. Migração e fluxo público foram validados em PostgreSQL local em 23/10/2026. Veja a [Aula 9](tutorials/09-motoristas.md) e a [ADR 0010](adr/0010-cadastro-de-motoristas.md).

### Trabalho integrado atual — cadastro mestre de veículos

RF04, RF05, RF15 e RB03 foram implementados como fatia vertical: React → Gateway → BFF → Frota → migração V2. Frota valida o JWT por JWKS no perfil RSA, aceita Administrador/Gestor, preserva registros ao inativar e filtra por status. Veja a [Aula 8](tutorials/08-veiculos.md) e a [ADR 0009](adr/0009-cadastro-mestre-de-veiculos.md). Em 23/10/2026, V2 e o fluxo público foram validados com PostgreSQL local.

### Trabalho integrado atual — usuários e perfis

RF02 implementado na interface, Gateway/BFF e Identidade: cadastro, consulta paginada, edição e desativação lógica. RF03 aplicado a essa funcionalidade, com verificação de Administrador ativo. V3 acrescenta perfil sem promover contas antigas; o primeiro Administrador local exige seed explícito. Veja a [Aula 7](tutorials/07-usuarios-e-perfis.md). Migração, índices e fluxo com PostgreSQL real foram validados em 23/10/2026. Não é conclusão da Sprint 1; não há novo pacote separado.

### Recorte atual — Sprint 1, parte 3: RSA e JWKS

A v0.3.0 adiciona assinatura assimétrica opt-in em Identidade e publicação interna da chave pública. O modo local anterior continua disponível; a troca exige novo login. Nenhum consumidor recebeu a chave privada. Veja a [Aula 5](tutorials/05-chaves-rsa.md). Validação distribuída, autorização, Frota, microfrontends e integração real com bancos permanecem pendentes.

### Histórico — Sprint 1, parte 2: login integrado

Em 20/10/2026, a v0.2.0 conecta a tela ao Gateway/BFF e à autenticação de Identidade. A assinatura permanece em Identidade; BFF encaminha o Bearer para validação, sem receber a chave. Sessão da interface somente em memória. Veja a [Aula 4](tutorials/04-login-integrado.md). Ainda faltam execução real com bancos, permissões, cadastros de Frota e microfrontends. Sprint 1 não concluída.

### Histórico — Sprint 1, parte 1

Iniciada por solicitação do usuário, mantendo as pendências da Sprint 0 abertas. Login interno de Identidade, BCrypt, JWT de curta duração, rota autenticada `/me`, migração aditiva de usuários e seed local opcional. Veja a [Aula 3](tutorials/03-autenticacao.md). Ainda faltam integração Gateway/BFF/interface, assinatura assimétrica para validação distribuída, perfis, cadastros de Frota e testes de banco reais. A Sprint 1 não está concluída.

### Histórico — Sprint 0

Continuação de 19/10/2026: primeira tela do shell React/TypeScript/Vite em `frontend/`, consultando o contrato técnico pelo Gateway. Veja a [Aula 2](tutorials/02-primeira-tela.md). Microfrontends independentes ainda não foram implementados. A publicação efetiva na Azure passa a integrar a Sprint 4 por solicitação do usuário; nenhum recurso de nuvem foi criado nesta etapa.

Implementado em `services/`: Gateway, BFF, quatro serviços, consulta técnica de disponibilidade, configuração Flyway e testes iniciais de dependências. O Compose está em `compose.sprint0.yaml`; o roteiro didático está em [Aula 1](tutorials/01-fundamentos.md).

A Sprint 0 completa ainda exige execução ponta a ponta com Docker, integração do shell com microfrontends independentes, contratos e ampliação das verificações. O workflow de backend foi criado; sua execução remota depende de publicar o repositório no GitHub. Os resultados locais constam em `VERIFICACAO-SPRINT0.md`.

### Critérios

1. O caso de uso funciona localmente e pode ser explicado por alguém iniciante.
2. Testes de domínio, integração, contrato e arquitetura pertinentes passam.
3. As decisões e os diagramas afetados são atualizados.
4. Falhas são observáveis, e dados pessoais/segredos não aparecem em logs ou no Git.

## Decisões antes de implementar regras incertas

Resolver as [pendências de negócio](DECISOES-PENDENTES.md) antes de codificar lançamentos retroativos, correções, cancelamentos e mudança automática do status do veículo. As decisões mínimas de vínculos estão registradas na ADR 0011; não se inventa uma regra apenas para completar o diagrama.
