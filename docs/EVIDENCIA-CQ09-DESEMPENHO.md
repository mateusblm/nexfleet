# Evidência CQ09 — desempenho das listas paginadas

Data da execução mais recente: 08/11/2026.

## Critério

O CQ09 exige 100 usuários simultâneos consultando listas paginadas, com percentil 95 (p95) inferior a 2 segundos. A execução local mede o caminho público completo:

`Gateway → BFF → microsserviço → PostgreSQL`

O teste usa uma sessão já autenticada para representar 100 usuários ativos. O login inicial e os aquecimentos não entram nas métricas. Cada requisição ainda percorre as validações JWT das camadas responsáveis. Nenhum cadastro é criado ou alterado.

## Cenário executado

- 100 usuários virtuais simultâneos;
- 3 ciclos por usuário;
- 6 listas paginadas por ciclo;
- página 0 com 20 itens;
- 1.800 requisições medidas;
- cache HTTP desabilitado pelo cliente;
- limite verificado no total e individualmente por endpoint: `p95 < 2.000 ms`;
- timeout de segurança por requisição: 10 segundos.

Como a conta local tinha perfil `ADMINISTRADOR`, a lista de usuários também foi incluída. Com outro perfil, o executor mede as cinco listas de Frota e Operações autorizadas para a equipe de Frota.

## Resultado local

| Medida | Resultado |
|---|---:|
| Requisições | 1.800 |
| Falhas HTTP/transporte | 0 |
| Tempo total | 9,895 s |
| Vazão média | 181,91 req/s |
| p50 geral | 439,91 ms |
| p95 geral | **1.000,62 ms** |
| p99 geral | 1.175,07 ms |
| Máximo observado | 1.450,35 ms |

| Lista | Requisições | Falhas | p95 |
|---|---:|---:|---:|
| Usuários | 300 | 0 | 879,36 ms |
| Veículos | 300 | 0 | 1.038,33 ms |
| Motoristas | 300 | 0 | 1.060,27 ms |
| Vínculos | 300 | 0 | 1.058,17 ms |
| Abastecimentos | 300 | 0 | 886,05 ms |
| Manutenções | 300 | 0 | 968,24 ms |

**Conclusão local: aprovado.** O p95 geral e o p95 de cada lista ficaram abaixo de 2 segundos, sem falhas. A medição acima pertence à execução do E2E completo com `-IncludePerformance`; resultados variam entre execuções conforme a carga do computador.

## Como repetir

Com o backend já iniciado e o usuário local provisionado:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\scripts\Test-Performance.ps1"
```

O script lê as credenciais de `.env.sprint0` apenas no processo, não as imprime e as remove das variáveis temporárias ao terminar. Para executar todo o fluxo integrado, incluindo CQ09:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File ".\scripts\Test-E2E.ps1" -IncludePerformance
```

## Limite desta evidência

O resultado caracteriza o ambiente local usado na data acima. A publicação da Sprint 4 deve repetir o mesmo ensaio na URL HTTPS de homologação, porque rede, região, dimensionamento e serviços gerenciados da Azure podem alterar a latência. Uma aprovação local não é apresentada como prova da infraestrutura de nuvem ainda não criada.

## Resultado na homologação Azure (10/11/2026)

Usamos o mesmo `quality/load/cq09.mjs`, com os mesmos parâmetros: 100 usuários, 3 ciclos, 6 listas, 1.800 requisições e limite de 2.000 ms. A base foi a borda pública HTTPS do API Management (`/api/v1/...`). O caminho completo é:

`APIM → Gateway → BFF → microsserviço → PostgreSQL privado`

Registramos todas as execuções, inclusive as reprovadas:

| Origem da carga | Dimensionamento | Falhas | p50 | p95 | Resultado |
|---|---|---:|---:|---:|---|
| Rede doméstica do operador → Central US | econômico, com réplicas escalando a partir de zero | 9 | 1.385 ms | 6.821 ms | Reprovado |
| Rede doméstica do operador → Central US | econômico, aquecido | 0 | 773 ms | 2.772 ms | Reprovado |
| Rede doméstica do operador → Central US | carga, aquecido | 0 | 451 ms | 2.603 ms | Reprovado |
| Job na própria Central US (aquecimento) | carga | 0 | — | 1.279 ms | Aprovado |
| **Job na própria Central US (oficial)** | **carga** | **0** | — | **900 ms** | **Aprovado** |

Os dois perfis de dimensionamento são:

- **econômico** (padrão): 0,5 vCPU e 1 GiB por serviço, no máximo 2 réplicas. Identidade, Frota e BFF escalam a zero.
- **carga**: 1 vCPU e 2 GiB, de 1 a 4 réplicas.

O perfil carga foi aplicado somente na janela do ensaio, por decisão do responsável pela conta, e revertido em seguida. Ver a ADR 0037.

### Diagnóstico das reprovações

Durante a execução, os logs dos próprios serviços mediram o tempo de cada um:

- **Microsserviços de domínio:** p95 de 8 a 13 ms.
- **BFF:** p95 de 302 ms.
- **Gateway:** p95 de 1.095 ms.

O restante do tempo medido no cliente doméstico vem do APIM e da rede Brasil → Central US. Essa conexão apresentou resets TLS (`WinError 10054`) durante todo o dia.

**Conclusão Azure: aprovado no ambiente de homologação definido**, com a carga gerada na mesma região e no perfil carga. Ressalvas:

- Para usuários distantes da região, a latência de rede soma cerca de 1,5 s ao p95.
- O Gateway é o ponto interno a otimizar: pool de conexões e chamadas ao BFF por HTTPS interno.
- O perfil econômico não atende ao CQ09 com 100 usuários simultâneos.

Para repetir, publique a imagem `quality/load/Dockerfile` (contexto `quality/load`) no ACR e execute-a como job do Container Apps com `--base-url` apontando para o APIM. As credenciais entram como segredos do job.
