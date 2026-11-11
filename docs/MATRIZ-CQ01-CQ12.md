# Matriz de evidências CQ01–CQ12

Atualização: 08/11/2026. Esta matriz transforma os cenários de qualidade da página 37 do documento normativo em evidências verificáveis do repositório. Ela não considera um cenário concluído apenas porque a arquitetura foi desenhada para atendê-lo.

## Legenda

- **Aprovado local**: existe teste automatizado que reproduz o resultado principal do cenário.
- **Aprovado local; repetir em homologação**: o ensaio passou no Compose local, mas o ambiente exigido pelo cenário final é a homologação.
- **Parcial; prova integrada pendente**: a proteção está implementada ou há testes de partes do fluxo, porém ainda falta reproduzir o estímulo completo e medir o resultado esperado.

## Situação consolidada

| CQ | Cenário resumido | Evidência atual | Estado | Próxima prova necessária |
|---|---|---|---|---|
| CQ01 | Uma chamada sem autenticação deve receber `401` antes de executar o caso de uso. | `LoginHttpTest.meSemTokenRetorna401` e `AuthHttpTest.semBearerNaoChamaServicoEComBearerConfirmaUsuario`. | **Aprovado local** | Repetir o contrato de segurança após a publicação HTTPS. |
| CQ02 | O Gestor não pode alterar usuários, mesmo contornando a interface. | `UsuariosHttpTest.semToken401EGestor403SemConsultarBanco`, `LoginHttpTest.rotaNaoAutorizadaRetorna403MesmoComToken` e `AuthHttpTest.cadastroSemToken401ERecusaAdministrativaPreservadaSemCsrf`. | **Aprovado local** | Repetir no ambiente publicado. |
| CQ03 | Abastecimento com quilometragem menor que a atual deve retornar `422` sem gravar abastecimento, hodômetro ou outbox. | `JdbcAbastecimentosIT.cq03QuilometragemRegressivaRetorna422SemAlterarAsTresTabelas` executa Flyway e as consultas em PostgreSQL efêmero. Veja [Evidência CQ03/CQ04](EVIDENCIA-CQ03-CQ04-TRANSACAO.md). | **Aprovado local** | Repetir a suíte integrada depois de qualquer mudança na regra ou persistência. |
| CQ04 | Uma falha depois do início do abastecimento deve desfazer integralmente a transação no banco de Operações. | `JdbcAbastecimentosIT.cq04FalhaNaOutboxDesfazAbastecimentoHodometroEEvento` injeta falha na outbox e verifica as três tabelas. Veja [Evidência CQ03/CQ04](EVIDENCIA-CQ03-CQ04-TRANSACAO.md). | **Aprovado local** | Manter a execução obrigatória no workflow backend. |
| CQ05 | Operações de veículo inativo devem continuar consultáveis com data e responsável. | `Test-Cq05.ps1` executa quatro fases em bancos separados: cria o veículo, registra o abastecimento, inativa o cadastro e consulta pela API preservando `realizadoEm` e `motoristaId`. Veja [Evidência CQ05](EVIDENCIA-CQ05-HISTORICO.md). | **Aprovado local** | Manter a prova interserviços obrigatória no workflow backend. |
| CQ06 | Ao enviar formulário inválido, dados válidos permanecem; campos incorretos são marcados e uma mensagem compreensível é exibida. | `Login.test.tsx`, `Usuarios.test.tsx`, `Veiculos.test.tsx` e `OperacoesApp.test.tsx`, além do hook `useFormValidation` aplicado aos sete formulários. Veja [Evidência CQ06](EVIDENCIA-CQ06-USABILIDADE.md). | **Aprovado local** | Fazer validação exploratória final com teclado e leitores de tela nos navegadores-alvo. |
| CQ07 | Com banco indisponível, a prontidão deve falhar e o log deve ser correlacionável sem expor segredo. | `Test-Cq07.ps1` executa Frota com PostgreSQL efêmero, para somente esse banco e confirma readiness/API `DOWN/503`, correlação na resposta/log e ausência das sentinelas de senha/token. Veja [Evidência CQ07](EVIDENCIA-CQ07-INDISPONIBILIDADE.md). | **Aprovado local** | Repetir a falha controlada depois da implantação no orquestrador de homologação. |
| CQ08 | Uma mudança na regra de abastecimento deve permanecer na fatia vertical e possuir regressão automatizada. | `GerenciarAbastecimentosTest`, `JdbcAbastecimentos` e `ArchitectureTest` de Operações delimitam aplicação, domínio e infraestrutura. | **Aprovado local** | Manter o teste de regressão a cada alteração da regra. |
| CQ09 | Cem usuários consultando listas paginadas devem obter p95 inferior a 2 segundos. | `quality/load/cq09.mjs`, `Test-Performance.ps1` e [Evidência CQ09](EVIDENCIA-CQ09-DESEMPENHO.md): 1.800 requisições, zero falhas e p95 geral de 1.000,62 ms. | **Aprovado local; repetir em homologação** | Executar a mesma carga na homologação Azure e guardar o relatório. |
| CQ10 | A recuperação após falha lógica deve respeitar RPO de até 24 horas e RTO de até 4 horas. | `Backup-Databases.ps1`, `Test-Recovery.ps1` e [Evidência CQ10](EVIDENCIA-CQ10-RECUPERACAO.md): cinco bancos/16 tabelas, RPO de 0,25 min e RTO de 0,72 min. | **Aprovado local; repetir em homologação** | Configurar backup/PITR gerenciado e executar restauração na homologação. |
| CQ11 | Uma importação entre componentes internos de serviços diferentes deve reprovar a verificação arquitetural na CI. | `ArchitectureTest.java` existe nos seis serviços e na Function; o workflow backend executa essas regras. | **Aprovado local** | Confirmar a execução remota depois de publicar o repositório. |
| CQ12 | Entrega duplicada do mesmo evento deve produzir apenas um efeito por `eventoId`. | `ProjetarAbastecimentoTest.ignoraEntregaDuplicada` e `Test-Sprint3Serverless.ps1` comprovam idempotência em Indicadores e na Function. | **Aprovado local** | Repetir com o broker e a Function publicados. |

## Cenários complementares do documento

| Cenário | Evidência |
|---|---|
| Broker indisponível não cancela transação já confirmada; outbox permanece pendente e tenta novamente. | `PublicarEventosPendentesTest.preservaPendenteEAgendaRetryQuandoBrokerFalha`. |
| Repetição ou timeout da Function não duplica a notificação. | Chave `evento_id`, testes da Function e `Test-Sprint3Serverless.ps1`. |
| Falha de um microfrontend não impede o shell e as áreas independentes. | `MicrofrontendHost.test.tsx` cobre montagem, desmontagem e remoto indisponível. |

## Leitura do resultado

No estado atual, CQ01, CQ02, CQ03, CQ04, CQ05, CQ06, CQ07, CQ08, CQ11 e CQ12 estão aprovados localmente. CQ09 e CQ10 também passaram localmente, mas precisam ser repetidos na homologação. Portanto, os doze cenários possuem evidência local; as repetições de ambiente exigidas por CQ09 e CQ10 permanecem abertas na Sprint 4.
