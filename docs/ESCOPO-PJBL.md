# NexFleet — escopo único de implementação

Fonte: `docs/reference/ArqCloud_PJBL-Completo.pdf`, cópia sem alterações do arquivo enviado pelo usuário, com 40 páginas. SHA-256 registrado abaixo. Conferência: 20/10/2026.

SHA-256: `EED8C70C9078DFEC74553ADC70C3B3A0EBD849915CD3F254BF8F77DE283F1FF8`.

O PJBL prevalece sobre sugestões da conversa e resumos divergentes. O PDF anterior em `output/pdf` é histórico, não substitui esta referência. A pasta ativa é `Downloads/NexFleet`; o workspace solto em Downloads foi corrigido para apontar para ela, em vez de abrir toda a pasta Downloads.

## Entrega solicitada

Uma única base de código, com histórico Git e todas as sprints integradas. Um POM por aplicação Java é esperado na arquitetura de microsserviços; o build é iniciado pelo agregador `services/pom.xml`. Não criar cópias de aplicações por sprint. As versões anteriores são histórico, não pastas a combinar manualmente.

## Requisitos e situação observada

| Requisito do PJBL | Responsável | Evidência para concluir | Situação atual |
|---|---|---|---|
| RF01: login | Identidade, BFF, Gateway, shell | Login completo com banco e conta ativa | Implementado e validado em PostgreSQL local |
| RF02: cadastrar, editar, consultar e desativar usuários | Identidade | CRUD administrativo, senha hash, duplicidade 409 | Implementado; migração V3 validada em PostgreSQL local |
| RF03: Administrador/Gestor | Todos os serviços protegidos | 401/403 inclusive em chamada direta | Implementado em Identidade, BFF, Frota, Operações e Indicadores |
| RF04–05: veículos e desativação | Frota | Campos completos, placa única, filtros e histórico preservado | Implementado e validado em PostgreSQL local |
| RF06–07: motoristas | Frota | Campos completos, CPF/CNH únicos e dados protegidos | Implementado e validado em PostgreSQL local |
| RF08: vínculos históricos | Frota | Unicidade ativa por veículo, CNH válida, histórico | Implementado e validado em PostgreSQL local em 28/10/2026 |
| RF09–11: abastecimentos/hodômetro/histórico | Operações | Transação, concorrência, 422, histórico por veículo | Implementado e validado em PostgreSQL local na v0.8.0 |
| RF12–13: manutenção/histórico | Operações | Validação de campos/datas, persistência e evento | Implementado na v0.12.0 |
| RF14: dashboard | Indicadores | Projeções por eventos, custos e disponibilidade | Implementado localmente na v0.13.0; custos projetados e status compostos pelo BFF |
| RF15: consulta por status | Frota/interface | Filtro testado e paginado | Implementado e validado pela API pública local |

Histórico de 28/10/2026: a validação RS256/JWKS foi comprovada no BFF e em Frota; RF02–08 e RF15 estão implementados. Shell e três microfrontends possuem builds separados. A base da Sprint 1 foi concluída localmente; operações, EDA, indicadores e serverless permanecem nas sprints seguintes.

## Regras expressas, sem acréscimos presumidos

Referência: seção 14, página 8.

- RB01–02: dois perfis iniciais e acesso autenticado. Motorista é entidade de negócio, sem login no MVP.
- RB03–04: placa única; CPF e CNH únicos no serviço Frota.
- RB05: veículo inativo não recebe novas operações ou vínculos.
- RB06: **cada veículo** possui no máximo um vínculo ativo. A restrição inversa por motorista não está definida.
- RB07: motorista vinculado ativo e com CNH válida. O efeito do vencimento sobre vínculo existente está pendente no próprio documento.
- RB08–11: abastecimento completo, litros/valor/km positivos, km não inferior ao atual e atualização do hodômetro.
- RB12–13: manutenção completa e próxima data, quando informada, posterior à data registrada.
- RB14–16: histórico válido preservado, gastos a partir de registros válidos e veículo em manutenção fora dos disponíveis.

Não foram aprovadas como regras adicionais: cancelamento seguido de novo lançamento, mudança automática de status ao registrar manutenção, um veículo por motorista ou mês atual obrigatório no dashboard. Essas sugestões anteriores não substituem o PJBL.

## Arquitetura obrigatória

Shell e três microfrontends React/TypeScript/Vite independentes; API Gateway; BFF; Identidade, Frota, Operações e Indicadores em Java 21/Spring Boot; PostgreSQL/Flyway próprios; APIs sem SQL cruzado; outbox, broker, idempotência, retry e DLQ; função de notificação; Clean Architecture/Vertical Slice; testes de fronteiras Java e frontend.

Operações é a fonte da verdade do hodômetro. Frota exibe projeção por evento. UUIDs entre serviços não são FKs cruzadas. O retorno 201 confirma a transação local, não atualização instantânea do painel. Não transformar as quatro bases em banco compartilhado para simplificar a entrega.

## Todas as sprints, sem declarar conclusão prematura

| Sprint | Entrega do documento | Condição de conclusão ainda necessária |
|---|---|---|
| 0 | Estrutura, contratos, Compose, bases e CI | Subida local real, isolamento e migrações comprovados |
| 1 | Identidade, Frota e MFEs básicos | Usuários/perfis, cadastros, vínculos, interface e testes integrados |
| 2 | Operações e EDA | Abastecimento/manutenção, transação/outbox, broker, retries e idempotência |
| 3 | Leitura e serverless | Dashboard por eventos, notificação disparada e falhas/DLQ comprovadas |
| 4 | Qualidade e Azure | CQ01–CQ12, observabilidade, documentos coerentes, custos/segredos revisados; publicação real solicitada pelo usuário |

## Pendências que o próprio documento registra

Seção 12.2 (p. 5) e 16.11 (p. 38): lançamentos retroativos, correção/cancelamento e mudanças de estado entre validação e gravação precisam de decisão. A ADR 0011 fecha a política mínima de vínculos; não criar funcionalidades de edição/cancelamento operacional sem as decisões restantes.

A descrição dos atores (p. 1–2) separa administração de cadastros da operação cotidiana do Gestor. O resumo local da ADR 0002 é mais amplo. Antes de implementar permissões de escrita de Frota para o Gestor, resolver a divergência em ADR; gerenciar usuários continua exclusivo do Administrador, conforme RF02/CQ02.

## Assinatura Azure

Em 08/11/2026, o Azure CLI foi autenticado em uma assinatura estudantil habilitada e a descoberta conferiu regiões, provedores e 16 tipos. Depois de autorização explícita, cinco provedores foram registrados e um orçamento de R$ 100/mês foi configurado. Não há grupo de recursos nem workloads Azure implantados; as demais criações continuam bloqueadas.

Mapeamento do PJBL: Static Web Apps; API Management; Container Apps para BFF e serviços; PostgreSQL com bases/credenciais isoladas; Service Bus; Azure Functions; Monitor/Application Insights. Confirmar elegibilidade, cotas, preços, moeda, região, orçamento e responsabilidade de cobrança antes de provisionar. Não alterar limite/proteção de gastos sem decisão explícita.

Em 05/11/2026, a v0.11.0 validou RabbitMQ, confirmação, persistência, consumo idempotente, retry limitado e DLQ em Indicadores.

Em 06/11/2026, a v0.12.0 concluiu a Sprint 2 com manutenção imutável, histórico por veículo, outbox, fila própria, projeção idempotente e DLQ. Não foi criada mudança automática de status, pois essa regra não consta no PJBL.

Em 06/11/2026, a v0.13.0 iniciou a Sprint 3 com dashboard financeiro e operacional. Indicadores soma as projeções de eventos; o BFF compõe o status atual de Frota sem compartilhar bancos.

Em 06/11/2026, a v0.14.0 concluiu a Sprint 3 no ambiente local. A Function Java 21 consome `AbastecimentoRegistrado.v1`, registra uma única solicitação por evento e utiliza retry/DLQ do RabbitMQ. O teste integrado publicou uma duplicata e uma mensagem inválida. Envio externo, telemetria e publicação efetiva permanecem na Sprint 4.

Em 07/11/2026, a v0.15.0 iniciou a Sprint 4 com métricas Micrometer/Prometheus para os seis serviços Java, coleta local versionada e verificação automática dos alvos. Esse registro era histórico: posteriormente Docker Desktop foi instalado, o Compose completo ficou saudável e as provas integradas locais foram aprovadas. A publicação Azure foi concluída e validada em 10/11/2026 (ADR 0037). Consulte `STATUS-SPRINTS.md` para o estado corrente.

## Critério da entrega consolidada

Entregar ZIP único somente com código/versionamento e instruções coerentes; sem segredos, dependências baixadas ou cópias antigas. Acompanhar cada requisito com teste e separar implementado, validado localmente e publicado. Não chamar o pacote de completo enquanto houver requisitos obrigatórios pendentes.
