# Entrega v0.13.0 — Dashboard

## Resultado

A primeira fatia da Sprint 3 implementa RF14, RB15 e RB16 no ambiente local. O dashboard combina gastos projetados por eventos, situação atual da frota e próximas manutenções sem compartilhar bancos.

## Verificação executada em 06/11/2026

- microfrontend Painel: 2 testes e build Vite aprovados;
- shell: 27 testes e build Vite aprovados;
- build Docker Java 21: Indicadores 13, BFF 52 e Gateway 12 testes aprovados;
- consulta autenticada pelo Gateway retornou os custos esperados, contagens por status e próxima manutenção enriquecida com a placa;
- JWT RSA/JWKS permaneceu ativo em BFF, Frota e Indicadores;
- regras ArchUnit continuaram aprovadas.

## Limites preservados

Os valores cobrem todo o histórico válido, sem inventar período padrão. Não há cancelamento, relatório avançado, função serverless ou publicação Azure nesta versão. A Sprint 3 permanece em andamento.
