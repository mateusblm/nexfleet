# Aula 26 — histórico depois da inativação do veículo

## 1. Inativar não é excluir

O cadastro de veículo usa inativação lógica. O registro continua em `frota.veiculo`, mas seu status muda para `INATIVO`. Isso impede novas operações sem apagar o que já aconteceu.

Uma exclusão física seria perigosa: poderia quebrar auditoria, relatórios e referências históricas.

## 2. Cada serviço é dono do seu histórico

```text
Frota                         Operações
frota.veiculo                operacoes.abastecimento
status = INATIVO             veiculo_id
                              realizado_em
                              motorista_id
```

Os bancos são separados. Frota não apaga linhas de Operações e Operações não consulta diretamente tabelas de Frota. A validação do status ocorre ao aceitar uma nova operação; a consulta de algo já registrado permanece disponível.

## 3. O que representa data e responsável

No abastecimento:

- `realizadoEm` é a data e hora em que a operação ocorreu;
- `motoristaId` identifica o motorista responsável pela operação;
- `criadoEm` registra quando o sistema persistiu o lançamento.

O contrato de consulta devolve esses valores, permitindo auditoria mesmo que a situação atual do veículo seja diferente.

## 4. Como a prova funciona

`Test-Cq05.ps1` mantém dois contêineres PostgreSQL durante todo o ensaio e executa quatro testes em ordem:

```text
criar veículo ativo em Frota
            ↓
registrar abastecimento em Operações
            ↓
inativar veículo em Frota
            ↓
consultar abastecimento em Operações
```

A última fase exige HTTP `200` e compara exatamente o `veiculoId`, `realizadoEm` e `motoristaId` usados antes da inativação.

## 5. Por que não usar o banco local

Um abastecimento real cria hodômetro e evento de outbox. Se o teste usasse os volumes ativos, também poderia alimentar RabbitMQ, Indicadores e notificações. Os bancos temporários permitem reproduzir o comportamento sem poluir dados nem filas.

## 6. Executar

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-Cq05.ps1"
```

Ou com a verificação geral e as demais provas de banco:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-Project.ps1" -SkipInstall -IncludeDatabaseIntegration
```

Consulte a [ADR 0027](../adr/0027-historico-interservicos-cq05.md), a [evidência](../EVIDENCIA-CQ05-HISTORICO.md) e a [matriz CQ01–CQ12](../MATRIZ-CQ01-CQ12.md).
