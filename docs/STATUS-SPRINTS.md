# NexFleet — estado das sprints

Atualização: 10/11/2026. A referência normativa é `reference/ArqCloud_PJBL-Completo.pdf`, com 40 páginas e SHA-256 `EED8C70C9078DFEC74553ADC70C3B3A0EBD849915CD3F254BF8F77DE283F1FF8`.

## Resumo executivo

| Sprint | Estado | Entrega comprovada | O que ainda falta |
|---|---|---|---|
| 0 — Fundamentos | Concluída localmente | Monorepositório, contratos, seis aplicações Java, bancos isolados, Compose, Gateway, BFF, health checks, CI e ArchUnit. | A execução de CI remota depende da publicação do repositório, mas não reabre a sprint local. |
| 1 — Identidade e Frota | Concluída localmente | Login BCrypt/JWT RSA/JWKS, usuários e perfis, veículos, motoristas, vínculos históricos, shell e três MFEs. | Publicação HTTPS é parte da Sprint 4. |
| 2 — Operações e EDA | Concluída localmente | Abastecimentos, hodômetro não regressivo, manutenções, outbox, RabbitMQ, retry, consumidor idempotente e DLQ. | Correção/cancelamento e mudanças de estado dependem de decisão de negócio; não são lacunas presumidas do MVP. |
| 3 — Leitura e serverless | Concluída localmente | Projeções, dashboard, Azure Function Java, idempotência, retry e DLQ de notificações. | Provedor/destinatário real de e-mail depende de decisão e publicação da Sprint 4. |
| 4 — Qualidade e publicação | Concluída: homologação Azure publicada e validada (10/11/2026) | Publicado em Central US: Static Web Apps (HTTPS), APIM, seis Container Apps, Function e ACS Email. O PostgreSQL privado recebeu as 17 migrações, o isolamento foi verificado na VNet e o primeiro Administrador foi provisionado. O fluxo crítico passou ponta a ponta por HTTPS. CQ09 aprovado na região (p95 de 900 ms, perfil carga). CQ10 aprovado (RPO 1,1 min, RTO 8,9 min). Ver as ADRs 0036 e 0037. | Dívidas: otimizar o Gateway, porque o perfil econômico não atende ao CQ09; domínio próprio de e-mail para produção. |

## Requisitos do MVP

- RF01–RF15: implementados no ambiente local.
- RB01–RB16: implementadas conforme o documento e as ADRs, sem inventar cancelamento ou mudança automática de status.
- RNF03–RNF08: cobertos localmente por hash de senha, autorização distribuída, PostgreSQL, histórico, interfaces, BFF/microsserviços/MFEs/EDA/serverless.
- RNF01, RNF02 e RNF09: a interface web existe e é responsiva, mas a prova final em dispositivos, HTTPS e cloud pertence à publicação da Sprint 4.

## Backlog restante da Sprint 4

1. Concluir a revisão das cotas dos SKUs em `Central US`. PostgreSQL `Standard_B1ms` foi encontrado; Container Apps mostrou ambiente gerenciado 0/1 e sandbox cores 0/10. Os demais limites ainda precisam de confirmação. A estimativa pública ficou entre R$ 360,81 e R$ 785,51/mês, sem créditos e antes de itens variáveis. O orçamento de R$ 100 alerta, mas não impede cobrança.
2. Publicar no ACR e executar na rede privada a imagem `infra/azure-database` antes dos workloads. A imagem, os cinco papéis, as 17 migrações e a idempotência já foram aprovados contra PostgreSQL 18 efêmero; falta somente a execução no Azure.
3. Publicar as seis imagens versionadas no ACR, o pacote da Function e o pacote frontend.
4. Cobrança dos workloads autorizada em 10/11/2026; falta concluir as barreiras técnicas e executar a implantação controlada.
5. Autorizar/configurar Azure Communication Services Email, remetente, destinatários e consentimento; nenhum e-mail real foi enviado.
6. Publicar por HTTPS e validar segredos, RBAC, custos, DLQs e fluxos essenciais.
7. Repetir CQ09 na homologação: localmente foram 1.800 consultas, zero falhas e p95 de 1.000,62 ms.
8. Confirmar backup/PITR de sete dias e repetir CQ10 na homologação; localmente, cinco bancos e 16 tabelas foram recuperados com RPO de 0,25 min e RTO conjunto de 0,72 min.

## Verificação da v0.29.0

- Suíte completa: 4 testes de qualidade/contratos, 176 testes dos serviços Java, 8 testes da Function, 47 testes frontend e quatro builds Vite aprovados.
- Banco Azure: imagem de migração executada duas vezes como usuário não-root; 17 versões Flyway aplicadas, segunda passagem sem alterações e acesso cruzado entre bancos recusado.

- Qualidade: 10 arquivos OpenAPI e 1 AsyncAPI com dois eventos; 4 testes automatizados aprovados, incluindo a integridade da matriz CQ01–CQ12 e dos diagramas.
- Serviços Java: 176 testes aprovados e seis JARs gerados, incluindo publicação/consumo Service Bus.
- Integração efêmera: 6 testes/fases PostgreSQL de CQ03/CQ04/CQ05 e 1 cenário CQ07 com Frota real, readiness e falha controlada do banco. Os recursos ativos não foram acessados.
- Azure Function: 8 testes aprovados e pacote gerado com gatilhos RabbitMQ e Service Bus; apenas RabbitMQ é habilitado localmente.
- Frontend: 47 testes aprovados, quatro builds Vite e pacote Azure gerados. Quatro testes de aceitação comprovam CQ06; os sete formulários críticos usam marcação visual/semântica de erros sem limpar valores válidos.
- Dependências: Node.js 24.22.2, JDK 21.0.13, quatro árvores npm e cache Maven baixados dentro do projeto.
- PDF: 40 páginas extraídas e revisadas visualmente; o hash coincide com a cópia em `docs/reference`.
- Diagramas: treze blocos Mermaid cobrem C4 níveis 1–4, UML e cinco DERs físicos; onze tabelas e 17 classes centrais são verificadas contra o repositório.
- Azure: assinatura estudantil `Enabled`; os seis provedores autorizados, incluindo `Microsoft.Network`, estão `Registered`, e a descoberta encontrou 19/19 tipos prontos. A política permite cinco regiões; `Central US` foi aprovada por atender os 19 tipos em um único local. O `what-if` `ProviderNoRbac` terminou com `Succeeded`, 62 criações previstas, uma implantação lógica e zero exclusões. A faixa pública de custo ficou entre R$ 360,81 e R$ 785,51/mês; o orçamento de R$ 100 permanece como alerta. Atualização de 10/11/2026: com o ACS, o inventário passou a 22 tipos; o último `what-if` previu 66 criações; e os workloads foram implantados e validados (ADR 0037).
- Trava de publicação: `paidResourcesApproved` foi autorizado em 10/11/2026. Na mesma data, foram confirmadas a cota `ManagedEnvironmentCount` 0/1 em `Central US`, com o ambiente existente contabilizado como Express (1/350), e a autorização do envio real de notificações por Azure Communication Services Email com domínio gerenciado. Com isso, o inventário passou para 22 tipos e `Microsoft.Communication` foi registrado ([ADR 0036](adr/0036-email-azure-communication-services.md)). Na mesma data, a homologação foi implantada e validada ([ADR 0037](adr/0037-publicacao-homologacao-azure.md)). Evidências: [CQ09](EVIDENCIA-CQ09-DESEMPENHO.md) e [CQ10](EVIDENCIA-CQ10-RECUPERACAO.md).
- Prova integrada local: Docker Desktop executou o Compose completo; Gateway → BFF → quatro serviços → bancos, topologia RabbitMQ, Function, login RSA e os seis alvos do Prometheus foram validados. Em 09/11/2026, o teste serverless confirmou duplicata persistida uma vez e mensagem inválida enviada à DLQ.
- Correlação integrada: um UUID fornecido ao Gateway foi devolvido uma única vez e apareceu nos logs dos seis serviços; Flyway V5 criou `operacoes.outbox_evento.correlation_id` como coluna obrigatória.
- Smoke E2E: login e sessão RSA, autorização de usuários, listas de Frota e Operações, Dashboard, consumidores/DLQs, Function idempotente e seis alvos Prometheus aprovados. As consultas HTTP não criam dados de negócio.
- CI: workflow dedicado cria segredos e bancos efêmeros, provisiona o Administrador, executa o E2E e remove os volumes ao final; a prova remota depende da publicação do repositório.
- CQ06 local: login, usuários, veículos e abastecimentos possuem aceitação automatizada; motoristas, vínculos e manutenções usam o mesmo comportamento validado.
- CQ03/CQ04 local: regressão de hodômetro retorna `422` sem novas linhas; falha injetada na outbox desfaz abastecimento, hodômetro e evento.
- CQ05 local: após criar veículo, registrar abastecimento e inativar o cadastro, a consulta HTTP preserva data, motorista responsável e data de criação.
- CQ07 local: readiness e API técnica mudam de `UP/200` para `DOWN/503`; resposta e log preservam a correlação sem expor senha ou token sentinela.
- CQ09 local: 100 usuários virtuais, seis listas paginadas, 1.800 consultas, zero falhas, p95 geral de 1.000,62 ms e todos os p95 individuais abaixo de 2 segundos.
- CQ10 local: cinco dumps com SHA-256, 16 tabelas restauradas e conferidas sem divergências, RPO observado de 0,25 minuto e RTO conjunto de 0,72 minuto.
- Rastreabilidade: a [matriz CQ01–CQ12](MATRIZ-CQ01-CQ12.md) registra dez cenários aprovados localmente e dois aprovados localmente com repetição pendente em homologação; não resta prova local exata aberta.
- Compatibilidade Windows: a chave RSA continua fora das imagens e um inicializador efêmero entrega uma cópia `0400` ao usuário não-root `10001`, contornando com segurança o modo `0600 root:root` aplicado pelo Docker Desktop a bind mounts de segredos.

## Subida local, em ordem

1. Instale Docker Desktop com WSL 2 e contêineres Linux; reinicie o Windows se solicitado.
2. Execute `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Install-Dependencies.ps1`.
3. Execute `Set-ExecutionPolicy -Scope Process Bypass` no terminal usado para os demais scripts.
4. Execute `.\scripts\Initialize-Local.ps1` e defina `LOCAL_USER_PASSWORD` em `.env.sprint0`.
5. Na primeira vez, execute `.\scripts\Start-Local.ps1 -ProvisionUser`; depois use `.\scripts\Start-Local.ps1`.
6. Em quatro terminais, execute `Set-ExecutionPolicy -Scope Process Bypass`, depois `. .\scripts\Use-Local-Toolchain.ps1` e inicie shell/Frota/Operações/Painel com `npm.cmd run dev` nas respectivas pastas.
7. Abra `http://127.0.0.1:5173`. Gateway, RabbitMQ e Prometheus ficam em `:8080`, `:15672` e `:9090`.
