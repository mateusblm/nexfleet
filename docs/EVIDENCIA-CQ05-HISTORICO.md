# Evidência CQ05 — histórico após inativação do veículo

Data da execução de referência: 08/11/2026.

## Objetivo

CQ05 exige que uma operação já registrada continue consultável, com data e responsável, depois que o veículo for inativado.

No NexFleet, Frota é dona do cadastro e do status do veículo. Operações é dona do abastecimento e preserva `realizado_em` e `motorista_id`. Não existe exclusão em cascata entre esses bancos independentes.

## Ambiente isolado

`Test-Cq05.ps1` cria dois PostgreSQL 18 temporários:

- um banco exclusivo do serviço Frota, com Flyway V1–V4;
- um banco exclusivo do serviço Operações, com Flyway V1–V5.

Cada contêiner recebe nome, porta e credenciais efêmeros. O script não lê `.env.sprint0`, não acessa volumes do ambiente local e remove os dois contêineres no bloco `finally`.

## Sequência comprovada

| Etapa | Serviço e prova | Resultado |
|---|---|---|
| 1 | `Cq05HistoricoVeiculoIT.cq05CriarVeiculoAtivo` em Frota | Veículo criado com status `DISPONIVEL` e mantido no cadastro. |
| 2 | `Cq05HistoricoVeiculoIT.cq05RegistrarOperacaoAntesDaInativacao` em Operações | Controller retorna `201`; abastecimento guarda veículo, data e motorista. |
| 3 | `Cq05HistoricoVeiculoIT.cq05InativarVeiculoSemExcluirCadastro` em Frota | Caso de uso altera o status para `INATIVO` sem excluir a linha. |
| 4 | `Cq05HistoricoVeiculoIT.cq05ConsultarHistoricoDepoisDaInativacaoMantemDataEResponsavel` em Operações | Controller retorna `200`; `realizadoEm`, `motoristaId` e `criadoEm` continuam presentes. |

A consulta final ocorre somente depois que a inativação foi confirmada no banco de Frota. O mesmo `veiculoId` é usado nas quatro fases.

## Execução

Na raiz do projeto, com Docker Desktop ativo:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-Cq05.ps1"
```

Para executar também CQ03 e CQ04 na verificação geral:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-Project.ps1" -SkipInstall -IncludeDatabaseIntegration
```

## Resultado da referência

- PostgreSQL: 18.6, imagem `postgres:18-alpine`;
- testes integrados executados: 4;
- falhas: 0;
- bancos ativos alterados: nenhum;
- contêineres temporários preservados: nenhum.

O workflow backend repete a prova em bancos efêmeros a cada mudança pertinente.
