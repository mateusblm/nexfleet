# Aula 27 — readiness e logs seguros durante falha do banco

## 1. Liveness e readiness não são iguais

- **Liveness** responde se o processo continua vivo.
- **Readiness** responde se o processo está pronto para receber tráfego útil.

Quando o PostgreSQL cai, a aplicação Java pode continuar viva, mas não está pronta para executar operações dependentes do banco. Por isso o endpoint de readiness inclui `db` e deve retornar `DOWN`.

## 2. O grupo de prontidão

Frota configura:

```properties
management.endpoint.health.probes.enabled=true
management.endpoint.health.group.readiness.include=readinessState,db
```

Com o banco disponível, o resultado é `UP` e HTTP `200`. Sem conexão, o resultado é `DOWN` e HTTP `503`. Um orquestrador pode retirar essa instância do balanceamento sem precisar encerrar o processo imediatamente.

## 3. A consulta técnica

`/api/v1/frota/info` executa `SELECT 1` através de `JdbcVerificarBanco`. Se o acesso falhar, o caso de uso devolve `DOWN` e o controller responde `503`.

O filtro de observabilidade preserva `X-Correlation-ID` na resposta e escreve uma linha semelhante a:

```text
correlationId=<uuid> ... path=/api/v1/frota/info status=503
```

Ele não registra cabeçalhos de autenticação, corpos, senhas, CPF ou CNH.

## 4. Como o teste induz a falha

```text
Frota temporário ─── PostgreSQL temporário
       │                    │
       │ readiness UP       │
       │                    X banco parado
       │ readiness DOWN
       │ info DOWN + correlationId
       └─ logs sem senha/token
```

O script nunca usa o contêiner `nexfleet-sprint0-frota-db-1`. Os nomes recebem um sufixo aleatório e a porta do serviço é escolhida pelo Docker.

## 5. Sentinelas de segurança

Uma senha e um token exclusivos são gerados em memória. Depois da falha, o script lê `docker logs` e procura esses valores. Encontrar qualquer um deles reprova o ensaio.

Essa técnica confirma ausência dos segredos conhecidos usados no cenário. Ela complementa, mas não substitui, revisão de código, controle de acesso aos logs e mascaramento no ambiente publicado.

## 6. Executar

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-Cq07.ps1"
```

Ou com todas as provas de banco:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-Project.ps1" -SkipInstall -IncludeDatabaseIntegration
```

Consulte a [ADR 0028](../adr/0028-falha-isolada-e-log-seguro-cq07.md), a [evidência](../EVIDENCIA-CQ07-INDISPONIBILIDADE.md) e a [matriz CQ01–CQ12](../MATRIZ-CQ01-CQ12.md).
