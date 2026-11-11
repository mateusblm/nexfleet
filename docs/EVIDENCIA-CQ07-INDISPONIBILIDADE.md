# Evidência CQ07 — indisponibilidade do banco e logs seguros

Data da execução de referência: 08/11/2026.

## Objetivo

CQ07 exige que a indisponibilidade do banco torne a prontidão não saudável e gere evidência correlacionável sem expor senha ou token.

## Ambiente isolado

`Test-Cq07.ps1` cria, com nomes aleatórios:

- uma rede Docker exclusiva;
- um PostgreSQL 18 temporário, sem volume e sem porta publicada;
- um contêiner Java 21 executando o JAR real do serviço Frota em uma porta aleatória ligada somente a `127.0.0.1`.

O serviço recebe senha de banco e token Bearer sentinelas exclusivos do ensaio. O script não lê `.env.sprint0`, não acessa os bancos ativos e remove contêineres e rede no bloco `finally`.

## Sequência comprovada

| Etapa | Resultado esperado | Resultado observado |
|---|---|---|
| PostgreSQL disponível | `/actuator/health/readiness` retorna `200` e `UP` | Aprovado |
| Parada somente do banco efêmero | Serviço Frota continua executando | Aprovado |
| PostgreSQL indisponível | `/actuator/health/readiness` retorna `503` e `DOWN` | Aprovado |
| Consulta técnica durante a falha | `/api/v1/frota/info` retorna `503` e `DOWN` | Aprovado |
| Correlação | Resposta e log preservam o UUID enviado em `X-Correlation-ID` | Aprovado |
| Sigilo | Log não contém senha do banco nem token Bearer sentinela | Aprovado |

O log também registra `path=/api/v1/frota/info status=503`, ligando o identificador de correlação à falha observada.

## Execução

Na raiz do projeto, com Docker Desktop ativo:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-Cq07.ps1"
```

Para executar todas as provas PostgreSQL isoladas:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-Project.ps1" -SkipInstall -IncludeDatabaseIntegration
```

## Resultado da referência

- PostgreSQL: 18.6, imagem `postgres:18-alpine`;
- runtime do serviço: Java 21, imagem `eclipse-temurin:21-jre-jammy`;
- prontidão antes da falha: `UP`, HTTP `200`;
- prontidão depois da falha: `DOWN`, HTTP `503`;
- API técnica depois da falha: `DOWN`, HTTP `503`;
- senha ou token encontrados no log: nenhum;
- recursos temporários restantes: nenhum.

O workflow backend repete o cenário em recursos efêmeros a cada mudança pertinente.
