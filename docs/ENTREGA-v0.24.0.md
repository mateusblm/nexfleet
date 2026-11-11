# Entrega v0.24.0 — C4, UML e DER alinhados ao código

## Resultado

A revisão arquitetural pendente da Sprint 4 foi concluída. C4 níveis 1–4, UML de componentes/classes/sequências e os DERs físicos agora representam o código, as rotas e as migrações atuais sem modificar o PDF normativo.

## Entregas

- `DIAGRAMAS-ARQUITETURA.md` com treze diagramas Mermaid versionáveis.
- Cinco DERs físicos separados por banco e inventário das onze tabelas de negócio.
- Relações entre bancos identificadas como referências lógicas sem FK cruzada.
- Correção da visão da fatia Registrar Abastecimento: JDBC e pacotes reais, sem declarar JPA ou um pacote `domain` inexistente.
- Teste de qualidade que confronta o documento com as migrações e 17 classes do fluxo crítico.
- ADR 0029 e Aula 28 com a regra de manutenção.

## Verificação

- As 40 páginas do PDF normativo foram extraídas e as páginas dos diagramas foram revisadas visualmente.
- O módulo `quality` executou 4 testes sem falhas.
- O inventário encontrou exatamente 11 tabelas criadas pelas migrações de negócio.
- O PDF original em `docs/reference` permaneceu inalterado.

## O que permanece aberto

CQ09 e CQ10 ainda precisam ser repetidos na homologação Azure. Também permanecem a decisão do provedor externo de notificações e a publicação HTTPS com assinatura, região, orçamento, segredos e backup gerenciado aprovados.
