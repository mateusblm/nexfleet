# Entrega v0.22.0 — histórico CQ05 após inativação

Data: 08/11/2026.

## Resultado

A oitava fatia da Sprint 4 aprova CQ05 localmente. Dois bancos PostgreSQL temporários reproduzem a sequência completa sem tocar nos dados ativos: criar veículo, registrar abastecimento, inativar veículo e consultar o histórico com data e motorista responsável.

## Entregas

- teste de integração de Frota para criação e inativação lógica;
- teste de integração de Operações para registro e consulta pelo controller;
- `Test-Cq05.ps1` com dois contêineres, portas e credenciais efêmeros;
- preservação comprovada de `realizadoEm`, `motoristaId` e `criadoEm`;
- inclusão da prova em `Test-Project.ps1 -IncludeDatabaseIntegration`;
- execução CQ05 no workflow backend;
- ADR 0027, Aula 26 e relatório de evidência.

## Verificação

- CQ05: 4 fases/testes PostgreSQL aprovados;
- suíte rápida: 3 testes de qualidade, 172 testes dos serviços Java, 8 testes da Function e 47 testes frontend;
- artefatos: seis JARs, pacote da Function e quatro builds Vite;
- bancos ativos acessados ou alterados: nenhum;
- contêineres temporários restantes: nenhum.

## O que permanece aberto

CQ07 ainda precisa de sua prova integrada exata. CQ09 e CQ10 precisam ser repetidos na homologação Azure. Permanecem também revisão final de C4/UML/DER, decisão do provedor externo de notificações e publicação HTTPS com custos, segredos e backup gerenciado aprovados.

Veja a [Evidência CQ05](EVIDENCIA-CQ05-HISTORICO.md), a [matriz CQ01–CQ12](MATRIZ-CQ01-CQ12.md) e o [estado das sprints](STATUS-SPRINTS.md).
