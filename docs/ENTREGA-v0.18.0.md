# Entrega v0.18.0 — desempenho CQ09

Data: 07/11/2026.

## Resultado

A quarta fatia da Sprint 4 formaliza o CQ09 com um ensaio automatizado de 100 usuários virtuais sobre as seis listas paginadas. O teste percorre Gateway, BFF, microsserviços e PostgreSQL, não altera dados e reprova quando existe falha ou quando qualquer p95 chega a 2 segundos.

## Componentes entregues

- `quality/load/cq09.mjs`: gerador de carga sem dependências npm adicionais;
- `scripts/Test-Performance.ps1`: carregamento seguro das credenciais e parâmetros do ensaio;
- opção `-IncludePerformance` em `Test-E2E.ps1`;
- execução CQ09 no ambiente efêmero de CI;
- ADR 0023, Aula 22 e relatório de evidência reproduzível.

## Prova local

Foram executadas 1.800 consultas com 100 usuários simultâneos e três ciclos. Não houve falha. O p95 geral foi 974,59 ms, e o maior p95 individual foi 1.004,27 ms, ambos abaixo do limite de 2.000 ms.

Consulte [EVIDENCIA-CQ09-DESEMPENHO.md](EVIDENCIA-CQ09-DESEMPENHO.md) para cenário, números por lista e limitações.

## Estado da Sprint 4

CQ09 está aprovado localmente. Antes de concluir a publicação, o mesmo ensaio deve ser repetido na homologação Azure. CQ06, CQ10, a revisão final de diagramas, a decisão do provedor de notificação e a implantação HTTPS continuam pendentes.
