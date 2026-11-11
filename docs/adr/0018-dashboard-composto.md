# ADR 0018 — Dashboard composto sem banco compartilhado

## Contexto

RF14 exige indicadores operacionais e financeiros. RB15 determina que os gastos venham dos registros válidos, e RB16 impede contabilizar veículo em manutenção como disponível. O serviço Indicadores já recebe abastecimentos e manutenções por eventos, enquanto Frota é a fonte da verdade do status atual.

## Decisão

- Indicadores soma gastos e quantidades em suas projeções PostgreSQL, sem consultar os bancos de Operações ou Frota.
- A primeira tela usa todo o histórico válido porque o PJBL não define um período obrigatório. Filtros de período permanecem uma evolução dependente de decisão de negócio.
- A próxima manutenção considera a projeção mais recente de cada veículo quando ela possui data futura, limitada às cinco datas mais próximas.
- Frota fornece a lista atual de veículos; apenas `DISPONIVEL` entra no cartão de disponíveis. `EM_MANUTENCAO` possui cartão próprio.
- O BFF compõe os dois contratos HTTP e acrescenta a placa à próxima manutenção. Ele não executa SQL nem acessa bancos de outros serviços.
- Indicadores valida o mesmo JWT RSA/JWKS aceito pelos demais serviços protegidos.
- O microfrontend Painel acessa somente `GET /api/v1/dashboard` pelo Gateway.

## Consequências

O dashboard respeita Database per Service e pode apresentar pequena defasagem nos gastos, pois as projeções são atualizadas por eventos. O status da frota é atual no momento da consulta. Como a API de Frota ainda não possui endpoint agregado, o BFF pagina a lista inteira; um contrato de contagem poderá substituir isso se o volume crescer. A função serverless continua fora desta versão, portanto a Sprint 3 ainda não está concluída.
