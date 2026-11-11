# ADR 0038 — exclusão definitiva de cadastros sem histórico

Data: 11/11/2026
Estado: aceita

## Contexto

Até a v0.29.0, veículos, motoristas e usuários só podiam ser **inativados**. A inativação preserva o cadastro para atender ao **CQ05**: o histórico de um veículo (vínculos, abastecimentos e manutenções) deve continuar consultável depois da inativação, com data e responsável.

Na homologação, o responsável pediu um botão **Excluir** nas telas de Veículos, Motoristas e Usuários. O objetivo é remover cadastros feitos por engano ou de teste, que nunca chegaram a ter histórico. Foram avaliadas duas regras:

1. excluir somente o que está inativo e não tem histórico;
2. excluir o registro com todo o histórico ligado a ele.

A regra 2 quebraria o CQ05. O responsável escolheu a regra 1.

## Decisão

A exclusão definitiva só acontece quando o registro está **inativo** e **sem histórico**. A rota é separada da inativação: `DELETE .../{id}/definitivo`.

| Cadastro | Condições | Onde é verificado |
|---|---|---|
| Veículo | status `INATIVO`, nenhum vínculo e nenhuma manutenção | O BFF consulta Operações (`/api/v1/operacoes/manutencoes?veiculoId=`). O Frota apaga com um único `DELETE ... WHERE status='INATIVO' AND NOT EXISTS (vínculo)`. |
| Motorista | status `INATIVO` e nenhum vínculo | Frota, com um único `DELETE` condicional |
| Usuário | conta desativada e diferente da do Administrador autenticado | Identidade |

- **Abastecimentos exigem vínculo:** Operações valida em `vinculos/validacao-operacao`. Por isso "sem vínculos" cobre os abastecimentos de veículos e motoristas. As manutenções não exigem vínculo e são verificadas pelo BFF.
- **O Frota não chama Operações**, o que evitaria uma dependência circular (Operações já chama Frota). A orquestração fica no BFF, que é quem compõe dados de vários serviços para a tela.
- **Falha fechada:** se o BFF não conseguir confirmar a ausência de manutenções, a exclusão não acontece e a resposta é `503`.
- **Respostas:**
  - `204`: excluído;
  - `404`: não encontrado;
  - `409`: possui histórico (mensagem "mantenha-o inativo");
  - `422`: ainda ativo, ou tentativa de excluir a própria conta.
- **A chave estrangeira** `veiculo_motorista → veiculo/motorista` continua como proteção final contra uma corrida.
- **Na interface**, o botão **Excluir** aparece somente em registros inativos, exige confirmação e é destacado em vermelho.

## Consequências

- O CQ05 permanece atendido: nada com histórico pode ser apagado.
- **Usuários:** os registros operacionais guardam apenas o UUID do autor (`criado_por`). Excluir uma conta desativada não apaga esses registros, mas o UUID deixa de corresponder a uma conta. Como o sistema não exibe o autor por nome, nenhuma tela é afetada.
- **Exclusão irreversível:** a única recuperação é a restauração point-in-time do PostgreSQL (CQ10), com retenção de 7 dias.
- **Contratos:** os contratos OpenAPI ganham três rotas públicas, e `ContractFilesTest` foi atualizado.

## Alternativas rejeitadas

- **Excluir em cascata com o histórico:** viola o CQ05 e a rastreabilidade das operações.
- **Exclusão lógica (flag `excluido`):** já é exatamente o que a inativação faz; não atenderia ao pedido de remover o registro.
- **Frota consultar Operações diretamente:** criaria um ciclo entre os dois serviços.
