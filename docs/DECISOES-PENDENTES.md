# Decisões de negócio pendentes

O documento identifica regras que precisam ser fechadas antes da implementação. Não escolheremos respostas por conveniência técnica, porque elas alteram histórico, autorização ou auditoria.

## Decididas para a fatia de vínculos — Sprint 1

1. Um motorista pode manter vínculos ativos com veículos diferentes, pois RB06 restringe apenas o veículo.
2. CNH vencida bloqueia novo vínculo; não encerra nem apaga automaticamente o existente.
3. Administrador e Gestor podem encerrar. O horário vem do servidor e não há encerramento retroativo.

Essas decisões e suas consequências estão na ADR 0011. Antes da Sprint 2 ainda será necessário decidir como uma operação reage se veículo, CNH ou vínculo mudarem entre validação e gravação.

## Decididas para a primeira fatia de abastecimentos — Sprint 2

1. Lançamento passado é aceito, mas nunca pode reduzir o hodômetro atual.
2. Registros são imutáveis. Correção/cancelamento não foi inventado nesta fatia e continua pendente para uma decisão específica de auditoria.
3. Litros e dinheiro usam no máximo duas casas decimais e `NUMERIC(12,2)` no banco.
4. Abastecimento exige vínculo válido entre motorista e veículo na data informada, além de veículo/motorista ativos e CNH válida.

Essas decisões e a transação com outbox estão registradas na ADR 0013.

## Decididas para a fatia de manutenções — Sprint 2

1. Registrar manutenção não muda automaticamente o status do veículo; essa regra não está no PJBL.
2. A devolução para `DISPONIVEL` permanece fora desta fatia, pois depende de um fluxo de status ainda não especificado.
3. “Próxima manutenção” usa data opcional no MVP; quando informada, deve ser posterior à data registrada.
4. O histórico é imutável: não há edição, cancelamento ou exclusão de manutenção nesta versão.

As consequências estão registradas na ADR 0017.

## Decididas para a primeira fatia de indicadores — Sprint 3

1. A primeira tela soma todo o histórico válido; o PJBL não obriga mês atual ou outro período padrão.
2. A tela mostra gastos por origem e total, quantidades de registros, veículos por status e próximas manutenções, cobrindo RF14, RB15 e RB16.
3. Apenas `DISPONIVEL` conta como disponível; `EM_MANUTENCAO` aparece separadamente.
4. Cancelamento continua fora do sistema. Se for especificado, seu efeito nas projeções exigirá contrato de evento e ADR próprios.

Essas decisões estão na ADR 0018. Filtros de período e relatórios avançados continuam como evoluções, não como regras presumidas.

## Decididas para a função de notificação — Sprint 3

1. A Function reage somente a `AbastecimentoRegistrado.v1`; ela não participa da transação do abastecimento.
2. `eventoId` é a chave de idempotência. Reentregar o mesmo evento não cria uma segunda solicitação.
3. No ambiente local, o adaptador captura assunto e corpo em banco próprio para permitir teste sem fingir um envio externo.
4. Evento inválido lança falha; a fila quorum limita a três entregas e então usa a DLQ.
5. Flyway roda como etapa de implantação antes da Function, e não durante o primeiro evento.

O destinatário, o provedor de e-mail, o domínio remetente e a política de consentimento não estão definidos no PJBL. Essas escolhas permanecem pendentes para a publicação Azure e não foram presumidas. Veja a ADR 0019.

Cada resposta que afetar dados, autorização, auditoria ou uma tecnologia obrigatória deve gerar uma ADR nova.

