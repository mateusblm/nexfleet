# ADR 0011 — Vínculos históricos de Frota

- Status: aceito
- Data: 23/10/2026

## Contexto

RF08 exige vincular motorista e veículo preservando histórico. RB05 impede novos vínculos em veículo inativo, RB06 permite no máximo um vínculo ativo por veículo e RB07 exige motorista ativo com CNH válida. O PJBL não define restrição inversa por motorista, encerramento retroativo nem encerramento automático quando a CNH vence.

## Decisão

Frota é dona de `frota.veiculo_motorista`. A migração V4 adiciona chaves estrangeiras somente dentro do banco Frota e um índice único parcial em `veiculo_id WHERE fim_em IS NULL`. Assim, a regra de um vínculo ativo por veículo permanece protegida mesmo sob duas requisições concorrentes.

Administrador e Gestor de Frota podem iniciar, consultar e encerrar vínculos. O início e o fim usam o relógio do servidor; a API não aceita datas retroativas. Um motorista pode estar vinculado a mais de um veículo porque o PJBL restringe apenas o veículo. CNH vencida ou motorista inativo bloqueia um novo vínculo, mas não altera automaticamente o histórico existente.

Encerrar preenche `fim_em` e `encerrado_por`; nenhuma linha é apagada. A leitura retorna placa e nome por junção local, sem copiar CPF ou CNH para a tabela de vínculo.

## Consequências

- RF08 e RB05–07 passam a possuir implementação executável para novos vínculos.
- O índice parcial resolve a concorrência da unicidade ativa sem impedir históricos antigos.
- Alterar futuramente a regra para um vínculo ativo por motorista exigirá nova ADR e migração de compatibilidade.
- O estado pode mudar entre validação e gravação; antes de usar o vínculo como autorização operacional na Sprint 2, será necessário fechar a política de versão/reconciliação indicada no risco arquitetural.
- O rollback seguro da aplicação preserva a tabela V4; remover a tabela só é seguro antes de existirem dados reais.
