# ADR 0023 — teste reproduzível de desempenho para CQ09

- Estado: aceita para a quarta fatia da Sprint 4.
- Data: 07/11/2026.
- Escopo: Sprint 4, v0.18.0.

## Contexto

O CQ09 pede 100 usuários simultâneos, listas paginadas e p95 inferior a 2 segundos. Os testes funcionais existentes comprovavam respostas corretas, mas não criavam concorrência nem calculavam percentis. A mesma prova também precisa poder rodar no Windows local, no macOS e no ambiente efêmero de CI sem instalar uma ferramenta adicional de carga.

## Decisão

Foi criado `quality/load/cq09.mjs` usando somente recursos nativos do Node.js 20 ou superior. `scripts/Test-Performance.ps1` lê a conta local de `.env.sprint0`, entrega as credenciais ao processo por variáveis temporárias e executa o cenário com valores padrão alinhados ao CQ09.

O executor:

1. autentica uma vez e valida a sessão;
2. aquece cada lista fora da medição;
3. inicia 100 usuários virtuais concorrentes;
4. faz três ciclos por usuário nas listas paginadas autorizadas;
5. mede p50, p95, p99, máximo, falhas e vazão;
6. reprova se houver erro ou se o p95 geral ou de qualquer lista for maior ou igual a 2 segundos.

O login não integra a janela medida: o cenário representa usuários já ativos consultando dados. Nenhuma rota de escrita é chamada. `Test-E2E.ps1 -IncludePerformance` permite acrescentar a prova ao fluxo completo, e o workflow `e2e.yml` a executa no ambiente efêmero.

## Consequências

- O CQ09 passa a ter critério automático, repetível e independente de licença.
- A conta e a senha não aparecem no relatório nem nos argumentos de linha de comando.
- A mesma sessão JWT é compartilhada pelos usuários virtuais; o teste mede leitura autenticada, não capacidade de login.
- Resultados variam conforme hardware, carga do host, dados, rede e dimensionamento.
- A aprovação local precisa ser repetida na homologação Azure antes da conclusão da publicação.

Os números da execução de referência estão em [Evidência CQ09](../EVIDENCIA-CQ09-DESEMPENHO.md).
