# Aula 17 — Dashboard com projeções e composição no BFF

## O que foi construído

O Painel deixou de ser uma tela vazia e passou a mostrar:

- gastos com abastecimentos, manutenções e total;
- quantidade de registros que formam esses gastos;
- veículos por situação;
- até cinco próximas manutenções, com placa, tipo e data.

O caminho da consulta é:

```text
Painel → Gateway → BFF ─┬→ Indicadores → PostgreSQL de Indicadores
                        └→ Frota       → PostgreSQL de Frota
```

## Por que não juntar tudo em uma consulta SQL

Cada microsserviço é dono do próprio banco. Indicadores não conhece as tabelas internas de Frota, e o BFF não possui banco. Isso evita que uma mudança de tabela em um serviço quebre os demais.

O BFF existe justamente para adaptar e combinar respostas para uma interface. Ele recebe os custos projetados de Indicadores, recebe os status de Frota e monta um único JSON para o Painel.

## Como Clean Architecture aparece no código

O caso de uso `ConsultarDashboard` conhece a porta `LeituraDashboard`, não o `JdbcTemplate`. O adaptador `JdbcLeituraDashboard` implementa a porta. No BFF, `ConsultarDashboardWeb` conhece `IndicadoresDashboardRemotos` e `FrotaDashboardRemota`, não o cliente HTTP do Spring.

Essa direção permite testar a regra com objetos simulados e protege o núcleo contra detalhes de framework.

## Como Vertical Slice aparece no código

Tudo que pertence à consulta do dashboard fica no pacote `consultardashboard`: API, aplicação e infraestrutura. A fatia atravessa a tela, Gateway, BFF e Indicadores, mas não mistura suas regras com cadastro, abastecimento ou manutenção.

## Consistência eventual em linguagem simples

O abastecimento é confirmado antes de o evento chegar a Indicadores. Por alguns instantes, o histórico pode mostrar o novo registro e o cartão ainda não ter mudado. Isso é consistência eventual: os dados convergem sem usar uma transação distribuída entre bancos.

## Segurança

O navegador manda o Bearer ao Gateway. BFF, Frota e Indicadores validam ou preservam o JWT conforme sua fronteira. Sem token válido, o dashboard não é consultado. A chave privada continua somente em Identidade; os demais usam a chave pública via JWKS.

## Quando usar

Use projeções quando a tela precisa ler rapidamente dados derivados de eventos. Use composição no BFF quando uma tela necessita informações de vários serviços. Evite composição para comandos de negócio: cada escrita deve continuar no serviço proprietário.

## Limite desta entrega

O total cobre todo o histórico válido porque o documento não obriga período mensal. Filtro por data, cancelamento e relatórios avançados não foram inventados. A próxima etapa da Sprint 3 é a função serverless de notificação, com idempotência e DLQ.
