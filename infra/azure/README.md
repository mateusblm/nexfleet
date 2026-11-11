# Infraestrutura Azure — preparação segura

Esta pasta contém o preflight e a infraestrutura Bicep da homologação. Nenhum arquivo é executado automaticamente e a trava `publicationApproved` começa em `false`.

A estimativa pública de custo pode ser atualizada com `scripts/Get-AzureCostEstimate.ps1`. Ela lê os SKUs e réplicas do Bicep, consulta a Azure Retail Prices API e não acessa nem altera a assinatura.

Arquivos:

- `preflight-profile.schema.json`: contrato do perfil preenchido pela equipe.
- `preflight-profile.example.json`: modelo sem assinatura, região, e-mail ou aprovações reais.
- `preflight-report-*.json`: descoberta conectada local, ignorada pelo Git e sem segredos.
- `resource-requirements.json`: provedores e tipos de recurso esperados pela arquitetura-alvo.
- `deployment-plan.example.json`: decisões e travas, sem autorização ou segredo real.
- `main.bicep`: grupo, orçamento e composição da plataforma.
- `modules/platform.bicep`: rede, dados, mensageria, Function, borda, identidades e RBAC.
- `modules/workloads.bicep`: seis Container Apps com imagens versionadas e configuração Service Bus.
- `modules/container-app.bicep`: módulo reutilizável de workload, ingress, probes e escala.
- `sql/bootstrap-service-roles.sql`: cria/atualiza cinco papéis sem privilégios administrativos e remove o acesso cruzado padrão.
- `../azure-database`: imagem não-root com PostgreSQL client e Flyway para executar as 17 migrações antes dos workloads.
- `bicepconfig.json`: regras do linter tratadas como barreiras de segurança.

Execute primeiro `scripts/Get-AzureReadiness.ps1`: ele consulta assinatura, regiões e provedores sem criar ou registrar nada. Depois copie o exemplo para `preflight-profile.json`, preencha as decisões e execute `scripts/Test-AzurePreflight.ps1`. Os arquivos reais são ignorados pelo Git porque contêm identificadores da assinatura.

As duas mutações já autorizadas possuem scripts separados e exigem `-Authorize`: `Register-AzureProviders.ps1` limita-se a cinco namespaces fixos e `Set-AzureBudget.ps1` configura os alertas de R$ 100 do perfil real. Nenhum dos dois implanta workloads.

Validação:

- `Test-AzureInfrastructure.ps1` faz o lint e o build do Bicep offline e exige 22/22 tipos modelados.
- `Test-AzureDatabaseBootstrap.ps1` valida o isolamento de forma estática.
- `Test-AzureDatabaseMigration.ps1` constrói a imagem e comprova, em PostgreSQL efêmero, a idempotência, o `verify.sh` e o `bootstrap-admin.sh`.
- `Invoke-AzureWhatIf.ps1` executa somente o `what-if`.

A homologação foi publicada em 10/11/2026. Todos os scripts que criam ou alteram recursos exigem `-Authorize`:

- `Deploy-AzureFoundation.ps1`
- `Publish-AzureImages.ps1`
- `Publish-AzureDatabaseMigration.ps1`
- `Publish-AzureFunction.ps1`
- `Publish-AzureFrontend.ps1`
- `Test-AzureRecovery.ps1`

A ordem de execução está no guia `docs/GUIA-INFRAESTRUTURA-AZURE-BICEP.md`, seção 7.1, e as decisões estão na ADR 0037.

Arquivos adicionais desta pasta:

- `migration-job.bicep`: jobs de banco executados dentro da VNet.
- Relatórios locais (`foundation-deployment-report-*`, `database-migration-report-*`, `homolog-report-*`, `cq10-recovery-report-*`): ignorados pelo Git e sem segredos.

A descoberta, o preflight, o `Test-AzureHomologation.ps1` e o `Invoke-AzureDatabaseQuery.ps1` (somente leitura) não alteram a infraestrutura. Consulte `docs/GUIA-PRE-PUBLICACAO-AZURE.md` antes de conectar uma conta nova.
