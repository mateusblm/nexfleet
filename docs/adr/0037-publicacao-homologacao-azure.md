# ADR 0037 — publicação da homologação Azure e correções encontradas na nuvem

Data: 10/11/2026
Estado: aceita

## Contexto

A cobrança foi autorizada, as cotas foram confirmadas e o e-mail foi aprovado (ADR 0036). Com isso, a homologação foi publicada em `Central US`. A implantação real mostrou problemas que o `what-if` e os testes locais não detectam. Também exigiu decisões que as ADRs anteriores deixavam em aberto.

## Decisões

1. **Ordem de publicação:**
   1. Fundação, com os workloads desligados.
   2. Imagens no ACR.
   3. Job `migrate`, com cinco papéis e 17 migrações.
   4. Job `verify`, que confere as versões e o isolamento com as credenciais de cada serviço.
   5. Seis Container Apps e a API no APIM (`-EnableWorkloads`), permitidos somente com um relatório de migração aprovado.
   6. Function e Static Web Apps.

   Os jobs de banco ficam em `infra/azure/migration-job.bicep` e rodam dentro da VNet, porque o PostgreSQL não tem acesso público.
2. **Primeiro Administrador:** o `LocalSeedConfig` nunca é habilitado na Azure. O job `job-nexfleet-db-admin` (`bootstrap-admin.sh`) recebe somente o hash BCrypt de custo 12 e conecta com o papel da Identidade. Se o e-mail já existe, o job não altera nada. A senha é gerada uma única vez e fica com DPAPI em `.secrets/azure-homolog-admin.clixml`, fora do Git.
3. **Transporte resiliente:** a rede do operador reinicia conexões TLS longas. As submissões ARM usam `--no-wait` e consultas curtas repetidas. Os uploads grandes (pacote da Function, Static Web Apps, carga CQ09) usam contêineres, cuja pilha de rede se manteve estável. Uma implantação anterior com o mesmo nome não é confundida com a atual.
4. **Perfil de dimensionamento `workloadProfile`:**
   - `economico`, o padrão: 0,5 vCPU e até 2 réplicas.
   - `carga`: 1 vCPU, de 1 a 4 réplicas.

   O perfil carga fica ativo apenas durante o CQ09 e depois é revertido, por decisão do responsável pela conta.
5. **CQ09 medido na região:** a carga é gerada por um job na própria `Central US` contra a borda pública HTTPS. As execuções a partir da rede doméstica ficam registradas como contexto, não como critério.

## Correções aplicadas

| Problema na nuvem | Causa | Correção |
|---|---|---|
| Duas atribuições de papel falharam (`RoleDefinitionDoesNotExist`) | GUID incorreto do papel Azure Service Bus Data Receiver | `4f6d3b9b-027b-4f4c-9142-0e5a2a2247e0` |
| Política da API no APIM recusada (`PreconditionFailed`) | Escritas concorrentes na mesma API | Operações em série (`@batchSize(1)`) e política depois das operações |
| Eventos publicados e descartados em silêncio; o painel não atualizava | Regras `$Default` reportadas como `Succeeded` pelo ARM, mas inexistentes; assinatura sem regra descarta tudo | Regras com nome próprio (`eventos-operacoes-v1`, `abastecimento-registrado-v1`), verificadas por consulta ARM |
| Function sem funções indexadas | Zip criado pelo PowerShell 5.1 com `\` nos caminhos | Pacote criado com `tar -a`, sem a pasta legada `NotificarAbastecimento` |

## Consequências

- A homologação está publicada por HTTPS: Static Web Apps, APIM, seis Container Apps, Function, PostgreSQL privado, Service Bus e ACS Email.
- O fluxo crítico passou ponta a ponta na nuvem: login, cadastros, vínculo, abastecimento, regressão de hodômetro recusada, histórico, painel atualizado por evento e e-mail enviado.
- O ARM pode relatar sucesso sem persistir regras de assinatura. A homologação passa a conferir as regras explicitamente.
- O perfil econômico não atende ao CQ09 com 100 usuários simultâneos. O Gateway (p95 de 1,1 s sob carga) é a próxima otimização.
- O gatilho RabbitMQ, mesmo desativado, gerava erro de indexação na Function. `Publish-AzureFunction.ps1` passou a publicar somente o gatilho Service Bus. Depois disso, o host carrega uma única função, sem erro.
- Toda a publicação ficou reproduzível por script, incluindo a Function, o frontend e a homologação funcional. Ver o guia de infraestrutura, seção 7.1.

## Alternativas rejeitadas

- Habilitar o `LocalSeedConfig` na Azure: contraria a regra do próprio código e deixaria a senha em configuração.
- Deixar o perfil carga permanente: o custo mensal ficaria muito acima do orçamento de R$ 100.
- Aprovar o CQ09 com a medição doméstica, ou descartá-la: as execuções reprovadas ficam documentadas e o critério usa a região de homologação.
