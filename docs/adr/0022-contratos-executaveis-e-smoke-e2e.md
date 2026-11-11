# ADR 0022 — contratos executáveis e smoke E2E

- Status: aceita
- Data: 07/11/2026
- Escopo: Sprint 4, v0.17.0

## Contexto

O NexFleet já possuía contratos OpenAPI, testes isolados e scripts para EDA, Function e observabilidade. Faltava uma barreira única contra três tipos de desvio:

1. YAML inválido ou incompleto;
2. rota/evento documentado de forma diferente do inventário público;
3. componentes saudáveis isoladamente, mas incompatíveis quando executados juntos.

Executar cadastros imutáveis contra o banco local do desenvolvedor em todo teste também criaria ruído e registros que não poderiam ser removidos pela API.

## Decisão

Adotamos três camadas complementares.

### 1. Contratos versionados

- dez documentos OpenAPI descrevem as rotas HTTP web e a API interna de Identidade;
- um documento AsyncAPI descreve os canais `operacoes.abastecimento.registrado.v1` e `operacoes.manutencao.registrada.v1`;
- os eventos incluem cabeçalhos, versão, agregado, instante e `X-Correlation-ID`, além do payload.

### 2. Verificação estática independente

O projeto Maven `quality` não entra nas imagens dos serviços. Ele rejeita chaves YAML duplicadas e verifica metadados, `operationId`, respostas 2xx, parâmetros de caminho, segurança, referências locais, rotas públicas e campos obrigatórios dos eventos.

`Test-Project.ps1` e o workflow de backend executam essa verificação antes dos demais testes.

### 3. Smoke E2E seguro

`Test-ApiContracts.ps1` autentica uma conta real e consulta sessão, usuários conforme o perfil, veículos, motoristas, vínculos, abastecimentos, manutenções e dashboard pelo Gateway. Cada requisição exige a devolução do mesmo `X-Correlation-ID`.

O script não altera dados de Frota ou Operações. `Test-E2E.ps1` agrega os testes de RabbitMQ, Function, DLQ e Prometheus. O evento serverless usa UUID aleatório e comprova idempotência sem depender de cadastro de negócio.

Na CI, `e2e.yml` cria segredos, chave RSA, bancos e volumes efêmeros, provisiona o Administrador, executa o fluxo e remove os volumes mesmo quando ocorre falha.

## Alternativas consideradas

### Validar somente os YAMLs visualmente

Rejeitada porque erros de referência, operações sem sucesso e rotas esquecidas podem passar despercebidos.

### Colocar o teste de contrato dentro de um microsserviço

Rejeitada porque acoplaria contratos globais a uma imagem de domínio e exigiria copiar `contracts/` durante cada build Docker.

### Criar dados de negócio no ambiente local em toda execução

Rejeitada como comportamento padrão porque abastecimentos e manutenções são imutáveis. Os testes de escrita permanecem nos serviços; fluxos destrutivos ou de carga devem usar ambiente efêmero dedicado.

## Consequências

### Positivas

- mudanças incompatíveis falham cedo;
- API HTTP e eventos possuem inventário verificável;
- o desenvolvedor testa integração sem poluir seus cadastros;
- a CI reproduz o Compose completo sem persistir segredos ou volumes.

### Limites

- o smoke E2E não substitui teste de carga, restauração ou jornada visual no navegador;
- a validação estrutural não gera automaticamente clientes nem prova semântica de todas as regras de negócio;
- a execução remota depende da publicação do repositório e da disponibilidade do runner.
