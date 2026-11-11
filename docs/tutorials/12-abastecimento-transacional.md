# Aula 12 — Primeiro abastecimento transacional

## O que foi construído

A primeira fatia da Sprint 2 atravessa Microfrontend de Operações → Gateway → BFF → serviço Operações → PostgreSQL. Ela registra abastecimentos, mantém o hodômetro e cria um evento na outbox.

## Por que três gravações formam uma transação

Uma transação funciona como um pacote indivisível: ou abastecimento, hodômetro e evento são confirmados juntos, ou nenhum deles é salvo. Isso impede situações como aumentar o hodômetro sem possuir o abastecimento correspondente.

## Como a quilometragem é protegida

O banco bloqueia a linha do hodômetro daquele veículo durante a gravação. Se duas pessoas enviarem operações ao mesmo tempo, a segunda espera a primeira terminar e então compara com o valor mais recente. Uma quilometragem menor gera `422` e rollback.

## O que é a outbox

A outbox é uma tabela de eventos pendentes dentro do mesmo banco do serviço. Nesta fatia o evento é salvo com o abastecimento. Na próxima, um publicador lerá os pendentes e os enviará ao broker. Assim, uma falha temporária do broker não apaga o registro do usuário.

## Quando usar

Use transação local quando várias alterações do mesmo serviço precisam ser atômicas. Use outbox quando um fato confirmado deve ser comunicado a outros serviços sem criar uma transação distribuída entre bancos e broker.

## O que ainda não está pronto

Esta entrega não conclui a Sprint 2. Ainda faltam publicador, broker, retry/DLQ, consumidores idempotentes e manutenção. Edição e cancelamento também aguardam uma decisão de auditoria.
