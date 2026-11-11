# Entrega v0.20.0 — usabilidade CQ06 e matriz de qualidade

Data: 08/11/2026.

## Resultado

A sexta fatia da Sprint 4 formaliza o CQ06 e cria a matriz rastreável CQ01–CQ12. Os sete formulários críticos agora mantêm dados válidos, marcam campos incorretos de forma visual e semântica e exibem uma orientação compreensível.

## Entregas

- hook de validação no shell, Frota e Operações;
- comportamento uniforme em login, usuários, veículos, motoristas, vínculos, abastecimentos e manutenções;
- quatro novos testes de aceitação do CQ06;
- ADR 0025, Aula 24 e relatório de evidência;
- matriz com evidência, estado e próxima prova para cada CQ;
- teste de qualidade que impede a remoção ou duplicação acidental de linhas CQ01–CQ12 da matriz.

## Verificação

- módulo de qualidade: 3 testes aprovados;
- serviços Java: 172 testes aprovados e seis JARs;
- Azure Function: 8 testes aprovados;
- frontend: 47 testes aprovados e quatro builds Vite.

## O que permanece aberto

CQ03, CQ04, CQ05 e CQ07 ainda precisam reproduzir seus estímulos completos em testes integrados. CQ09 e CQ10 precisam ser repetidos na homologação Azure. Também permanecem a revisão final de C4/UML/DER, a decisão do provedor externo de notificações e a publicação HTTPS com custos, segredos e backup gerenciado aprovados.

A situação detalhada está em [MATRIZ-CQ01-CQ12.md](MATRIZ-CQ01-CQ12.md) e [STATUS-SPRINTS.md](STATUS-SPRINTS.md).
