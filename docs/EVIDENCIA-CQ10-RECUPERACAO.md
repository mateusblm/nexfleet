# Evidência CQ10 — backup e recuperação

Data da execução mais recente: 08/11/2026.

## Critério

O CQ10 estabelece:

- RPO de até 24 horas: o ponto recuperável não pode estar mais de 24 horas atrás;
- RTO de até 4 horas: a restauração deve terminar em no máximo 4 horas.

RPO mede perda potencial de dados. RTO mede o tempo para recuperar o serviço. São métricas diferentes: criar backup rapidamente não comprova que ele pode ser restaurado, e possuir um arquivo antigo não atende ao RPO.

## Método seguro

`Test-Recovery.ps1` executou o seguinte fluxo sem parar os bancos principais:

1. criou dumps customizados com `pg_dump` para Identidade, Frota, Operações, Indicadores e Notificações;
2. inventariou as tabelas e as contagens de linhas;
3. calculou SHA-256 de cada arquivo;
4. iniciou cinco PostgreSQL 18 temporários, sem porta publicada e com rede desativada;
5. conferiu cada checksum antes da restauração;
6. restaurou com `pg_restore --exit-on-error`;
7. comparou as contagens de todas as tabelas;
8. removeu os restauradores e os backups temporários.

O ambiente NexFleet principal permaneceu ativo durante todo o ensaio. O teste não executa `DROP`, `DELETE`, `TRUNCATE` nem restauração sobre os bancos em uso.

## Resultado local

| Banco | Tabelas conferidas | Resultado |
|---|---:|---|
| Identidade | 2 | Restaurado e conferido |
| Frota | 4 | Restaurado e conferido |
| Operações | 5 | Restaurado e conferido |
| Indicadores | 3 | Restaurado e conferido |
| Notificações | 2 | Restaurado e conferido |
| **Total** | **16** | **Sem divergências** |

| Medida | Limite | Observado |
|---|---:|---:|
| RPO | até 24 h | **0,25 min** |
| RTO dos cinco bancos | até 4 h | **0,72 min** |

**Conclusão local: aprovado.** Os cinco arquivos passaram pela verificação SHA-256, as 16 tabelas foram restauradas sem erro e todas as contagens coincidiram.

## Como repetir

Com o backend Docker ativo:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\scripts\Test-Recovery.ps1"
```

Para incluir desempenho e recuperação no fluxo completo:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\scripts\Test-E2E.ps1" `
  -IncludePerformance -IncludeRecovery
```

## Criar uma cópia local preservada

O ensaio acima apaga sua cópia temporária ao terminar. Para manter um conjunto de backups:

```powershell
.\scripts\Backup-Databases.ps1
```

Os arquivos ficam em `backups/<data-hora>/`, pasta ignorada pelo Git. Eles contêm dados do sistema: devem ter acesso restrito, criptografia e cópia fora do computador em um uso real.

## Limite desta evidência

A execução comprova que o processo local recupera os dados e atende aos tempos definidos. Ela não configura sozinha uma agenda diária, retenção, armazenamento externo ou recuperação pontual na Azure. Na publicação, será obrigatório ativar backups gerenciados/PITR, retenção e redundância apropriadas e repetir o teste em homologação. Sem uma agenda automática de no máximo 24 horas, o RPO de produção não está garantido continuamente.

## Resultado na homologação Azure (10/11/2026)

O ensaio foi repetido na nuvem com `scripts/Test-AzureRecovery.ps1`. O servidor ativo não foi alterado. Os passos foram:

1. Contar as linhas de todas as tabelas dos cinco bancos na origem.
2. Fazer uma restauração point-in-time (PITR) do PostgreSQL Flexible Server para um servidor **temporário** na mesma VNet privada.
3. Executar `verify.sh` e a mesma contagem no servidor restaurado.
4. Excluir o servidor temporário.

| Medida | Resultado |
|---|---|
| Backup gerenciado | Automático, retenção de 7 dias, servidor sem acesso público |
| Contagem na origem | 10:41:02 UTC — 16 tabelas, 45 linhas |
| Ponto restaurado | 10:42:07 UTC |
| Submissão → servidor `Ready` | 10:42:37 → 10:49:33 (6,9 min) |
| Verificações concluídas | 10:51:29 UTC |
| `verify.sh` no restaurado | Aprovado: 17 migrações e isolamento entre os cinco bancos |
| Comparação de linhas | 16 tabelas, 45 = 45, **0 divergência** |
| **RPO ensaiado** | **1,1 min** (limite 24 h) |
| **RTO ensaiado** | **8,9 min** (limite 4 h) |

**Conclusão Azure: aprovado.** O backup gerenciado roda continuamente, então o RPO de produção depende da retenção (7 dias) e não de uma agenda manual.

Uma primeira restauração, às 05:38 UTC, não entrou na medição: o computador do operador ficou suspenso durante a espera e não houve registro confiável do instante `Ready`. Esse servidor foi excluído sem uso.
