# Entrega v0.21.0 — consistência CQ03 e atomicidade CQ04

Data: 08/11/2026.

## Resultado

A sétima fatia da Sprint 4 transforma CQ03 e CQ04 em provas integradas reais. Um PostgreSQL temporário recebe as mesmas migrações do serviço Operações, executa as falhas controladas e é apagado ao final sem acessar os bancos ativos.

## Entregas

- `JdbcAbastecimentosIT` com dois cenários de integração;
- prova de `422` e ausência de escritas para quilometragem regressiva;
- falha injetada na outbox e rollback de abastecimento, hodômetro e evento;
- `Test-Cq03Cq04.ps1` com contêiner, credenciais e porta efêmeros;
- opção `Test-Project.ps1 -IncludeDatabaseIntegration`;
- execução CQ03/CQ04 no workflow backend;
- ADR 0026, Aula 25 e relatório de evidência.

## Verificação

- CQ03/CQ04: 2 testes PostgreSQL aprovados;
- suíte rápida: 3 testes de qualidade, 172 testes dos serviços Java, 8 testes da Function e 47 testes frontend;
- artefatos: seis JARs, pacote da Function e quatro builds Vite.

## O que permanece aberto

CQ05 e CQ07 ainda precisam de suas provas integradas exatas. CQ09 e CQ10 precisam ser repetidos na homologação Azure. Permanecem também revisão final de C4/UML/DER, decisão do provedor externo de notificações e publicação HTTPS com custos, segredos e backup gerenciado aprovados.

Veja a [Evidência CQ03/CQ04](EVIDENCIA-CQ03-CQ04-TRANSACAO.md), a [matriz CQ01–CQ12](MATRIZ-CQ01-CQ12.md) e o [estado das sprints](STATUS-SPRINTS.md).
