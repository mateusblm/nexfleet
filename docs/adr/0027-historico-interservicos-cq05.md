# ADR 0027 — prova interserviços do histórico CQ05

- Status: aceita.
- Data: 08/11/2026.
- Escopo: Sprint 4, v0.22.0.

## Contexto

CQ05 atravessa duas fronteiras: Frota controla a situação do veículo, enquanto Operações preserva o abastecimento. Um teste somente com mocks não demonstra que os dados continuam independentes depois da mudança de status. Executar o ensaio nos bancos locais ativos poderia criar operações e eventos nos dados do desenvolvedor.

## Decisão

Foi criado `Test-Cq05.ps1`, que orquestra dois bancos PostgreSQL temporários e quatro fases selecionadas de testes Java:

1. criar e confirmar o veículo ativo no banco de Frota;
2. registrar o abastecimento pelo controller, caso de uso e repositório transacional de Operações;
3. inativar o veículo pelo caso de uso de Frota, sem excluir o cadastro;
4. consultar o histórico pelo controller de Operações e confirmar data e motorista.

As fases compartilham somente identificadores gerados para o ensaio. Cada serviço continua usando seu próprio banco e suas próprias migrações. Nenhum serviço importa classes internas do outro.

## Alternativas consideradas

- **Um único teste com os dois módulos no mesmo classpath**: rejeitado porque criaria acoplamento entre serviços e dificultaria o uso dos artefatos Spring Boot empacotados.
- **Um banco compartilhado para Frota e Operações**: rejeitado porque contrariaria a separação de dados da arquitetura.
- **Executar no Compose local ativo**: reproduziria o fluxo, mas criaria abastecimento, outbox e projeções nos dados do usuário.
- **Validar somente a existência das colunas**: insuficiente, pois CQ05 exige a sequência criar, registrar, inativar e consultar.

## Consequências

- CQ05 possui prova reproduzível sem modificar o ambiente ativo.
- O teste confirma a preservação de `realizadoEm`, `motoristaId` e `criadoEm` depois da inativação.
- A execução integrada exige Docker; os testes rápidos continuam sem iniciar bancos.
- O workflow backend passa a impedir regressões desse comportamento.

Veja a [Evidência CQ05](../EVIDENCIA-CQ05-HISTORICO.md), a [Aula 26](../tutorials/26-historico-apos-inativacao-cq05.md) e a [matriz de qualidade](../MATRIZ-CQ01-CQ12.md).
