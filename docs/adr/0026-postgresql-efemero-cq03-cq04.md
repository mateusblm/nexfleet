# ADR 0026 — PostgreSQL efêmero para CQ03 e CQ04

- Status: aceita.
- Data: 08/11/2026.
- Escopo: Sprint 4, v0.21.0.

## Contexto

Testes com repositório simulado não comprovam bloqueio de linha, constraints nem rollback real. Executar falhas deliberadas no banco local do desenvolvedor, por outro lado, colocaria dados cadastrados em risco.

CQ03 exige provar que a quilometragem regressiva não altera abastecimento, hodômetro ou outbox. CQ04 exige uma falha depois do início das escritas e rollback integral.

## Decisão

Foi criado `JdbcAbastecimentosIT`, executado explicitamente por `Test-Cq03Cq04.ps1` em um PostgreSQL temporário. O script:

1. cria credenciais aleatórias;
2. inicia `postgres:18-alpine` com porta dinâmica ligada apenas ao loopback;
3. fornece a conexão ao teste por variáveis temporárias de processo;
4. aplica as migrações reais V1–V5;
5. executa somente a classe de integração;
6. remove credenciais, contêiner e dados ao terminar.

O teste CQ04 injeta a falha por uma constraint exclusiva do banco efêmero. Não foi criado um ponto de falha artificial no código de produção.

## Alternativas consideradas

- **Testar somente com Mockito**: rápido, mas incapaz de demonstrar semântica transacional do PostgreSQL.
- **Usar o banco local ativo**: reproduziria o ambiente, mas poderia interferir em dados reais e no publicador da outbox.
- **Adicionar Testcontainers à aplicação**: válido, porém acrescentaria dependências quando o script Docker já fornece isolamento portátil e explícito.
- **Adicionar um parâmetro de produção para falhar a outbox**: rejeitado porque levaria instrumentação de teste ao código produtivo.

## Consequências

- CQ03 e CQ04 possuem prova reproduzível sem risco aos bancos ativos.
- A execução integrada exige Docker, enquanto os 172 testes rápidos continuam funcionando sem ele.
- A classe termina em `IT` e só roda quando o script a seleciona explicitamente.
- O workflow backend repete a prova em cada mudança pertinente.

Veja a [Evidência CQ03/CQ04](../EVIDENCIA-CQ03-CQ04-TRANSACAO.md), a [Aula 25](../tutorials/25-transacoes-postgresql-cq03-cq04.md) e a [matriz de qualidade](../MATRIZ-CQ01-CQ12.md).
