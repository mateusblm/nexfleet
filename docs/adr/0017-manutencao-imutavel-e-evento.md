# ADR 0017 — Manutenção imutável e evento dedicado

## Contexto

RF12 e RF13 exigem registrar os dados da manutenção e consultar o histórico por veículo. RB05 impede novas operações em veículo inativo e RB13 exige que a próxima manutenção, quando informada, seja posterior. O PJBL não determina mudança automática de status, edição ou cancelamento.

## Decisão

- Operações é a fonte da verdade da manutenção.
- A fatia `registrarmanutencao` separa API, aplicação e infraestrutura.
- Veículo é validado em Frota antes da gravação; `INATIVO` e inexistente são recusados.
- Manutenção e `ManutencaoRegistrada` v1 entram na mesma transação PostgreSQL.
- O publicador escolhe uma routing key dedicada pelo tipo do evento.
- Indicadores possui fila, DLQ e tabela de projeção próprias, com `evento_id` único.
- O histórico não possui atualização ou exclusão.
- O registro não altera o status do veículo.

## Consequências

Uma falha antes do commit não deixa evento órfão; uma falha do broker mantém o evento pendente. Reentregas não duplicam a projeção. A futura automação de status exigirá requisito e ADR próprios. Próxima manutenção por quilometragem também fica fora do MVP documentado.
