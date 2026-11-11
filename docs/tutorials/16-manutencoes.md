# Aula 16 — Manutenções e conclusão da Sprint 2

## O que foi construído

A manutenção agora percorre o sistema inteiro:

```text
React → Gateway → BFF → Operações → PostgreSQL
                                 └→ outbox → RabbitMQ → Indicadores
```

O formulário recebe veículo, tipo, data, quilometragem, descrição, oficina, valor e próxima data opcional. O histórico pode ser filtrado por veículo.

## Por que usar uma vertical slice

Uma vertical slice reúne tudo que pertence ao mesmo caso de uso. `registrarmanutencao` possui seu contrato, regra, porta e adaptadores. Isso evita misturar regras de manutenção com abastecimento apenas porque ambos pertencem a Operações.

Clean Architecture define a direção: a aplicação conhece interfaces (`Manutencoes` e `VeiculosFrota`), mas não conhece Spring, HTTP ou JDBC. Os adaptadores implementam essas interfaces.

## Regras implementadas

- somente Administrador ou Gestor de Frota;
- veículo existente e diferente de `INATIVO`;
- campos obrigatórios e limites de tamanho;
- quilometragem e valor não negativos;
- no máximo duas casas decimais no valor;
- próxima data estritamente posterior;
- histórico imutável;
- nenhum status é alterado automaticamente.

## Outbox e EDA

O SQL insere manutenção e evento na mesma transação. Depois do commit, o job publica `ManutencaoRegistrada` v1. Uma fila exclusiva evita misturar contratos. Indicadores usa `INSERT ... ON CONFLICT DO NOTHING`, então receber o mesmo `eventoId` novamente é seguro.

## Como testar

Inicie o ambiente com `./scripts/Start-Local.ps1` e as interfaces conforme o README. Execute `./scripts/Test-Project.ps1 -SkipInstall` para os testes e `./scripts/Test-Sprint2Eda.ps1` para conferir consumidores e DLQs.

## Quando usar

Use outbox quando dado e evento precisam permanecer consistentes, e idempotência quando o broker pode reenviar mensagens. Use filas diferentes quando consumidores ou contratos possuem evolução independente.
