# ADR 0028 — falha isolada e log seguro para CQ07

- Status: aceita.
- Data: 08/11/2026.
- Escopo: Sprint 4, v0.23.0.

## Contexto

Testar CQ07 no ambiente local ativo exigiria parar um banco usado pelo desenvolvedor e poderia interromper cadastros, eventos e outras verificações. Um mock do `DataSource` não comprovaria o comportamento real do Actuator, do pool de conexões nem do endpoint técnico durante uma falha PostgreSQL.

Também era necessário verificar o conteúdo efetivamente emitido no log, incluindo correlação e ausência de segredos.

## Decisão

`Test-Cq07.ps1` executa o JAR real de Frota em um contêiner Java conectado a um PostgreSQL temporário. O script:

1. empacota Frota sem executar novamente a suíte rápida;
2. cria rede, banco, credenciais e porta exclusivos;
3. espera readiness `UP/200`;
4. para somente o banco efêmero;
5. espera readiness `DOWN/503`;
6. consulta `/api/v1/frota/info` com `X-Correlation-ID` e token sentinela;
7. confirma `DOWN/503`, correlação na resposta e no log;
8. reprova se senha ou token aparecerem no log;
9. remove todos os recursos temporários.

## Alternativas consideradas

- **Parar `frota-db` do Compose ativo**: rejeitado porque afetaria o ambiente e os dados em uso.
- **Simular o banco com mock**: insuficiente para provar readiness real e falha de conexão.
- **Criar um endpoint exclusivo de teste**: rejeitado porque adicionaria instrumentação artificial ao código de produção.
- **Inspecionar somente a configuração de logging**: insuficiente; o requisito exige o resultado durante a falha.

## Consequências

- CQ07 possui prova local reproduzível sem indisponibilizar o NexFleet ativo.
- A verificação usa os endpoints e o padrão de log reais do serviço.
- Senha e token são sentinelas aleatórias, permitindo detectar vazamento sem usar segredos do usuário.
- A execução integrada exige Docker; a suíte rápida permanece independente dele.

Veja a [Evidência CQ07](../EVIDENCIA-CQ07-INDISPONIBILIDADE.md), a [Aula 27](../tutorials/27-readiness-e-logs-seguros-cq07.md) e a [matriz de qualidade](../MATRIZ-CQ01-CQ12.md).
