# ADR 0029 — diagramas versionados e verificados contra o código

## Status

Aceita em 08/11/2026.

## Contexto

O PJBL exige C4 níveis 1–4, UML e DER coerentes com processos, pacotes, classes, chamadas e migrações. As figuras do PDF representam a arquitetura planejada, mas a implementação evoluiu: a fatia de abastecimento usa JDBC e os pacotes `api`, `application` e `infrastructure`, sem o pacote `domain` previsto originalmente.

Diagramas mantidos somente como imagem podem ficar desatualizados sem que a suíte de testes perceba.

## Decisão

Manter a representação atual em `docs/DIAGRAMAS-ARQUITETURA.md`, usando Mermaid versionável em texto. O documento deve:

- distinguir implementação local de implantação Azure futura;
- mostrar C4 níveis 1–4 e UML de componentes, classes e sequências;
- separar os DERs físicos por banco proprietário;
- indicar relações lógicas que não possuem FK;
- apontar as classes e migrações usadas como fonte.

O módulo `quality` compara o inventário documentado com todas as instruções `CREATE TABLE` das migrações e exige as principais classes do fluxo de abastecimento.

## Alternativas consideradas

### Substituir as figuras dentro do PDF normativo

Descartada porque o PDF recebido deve permanecer como referência original, sem edição silenciosa.

### Manter apenas imagens exportadas

Descartada porque imagens não permitem uma verificação simples de tabelas e nomes de classes no CI.

### Gerar diagramas diretamente por reflexão

Adiada. A geração automática não explica bem limites de responsabilidade, relações lógicas e decisões futuras; o texto versionado continua necessário.

## Consequências

- A arquitetura implementada ganha uma fonte visual atualizada e revisável no Git.
- Uma nova tabela ou renomeação de classe central exige atualização explícita dos diagramas.
- A verificação estrutural não substitui revisão visual e semântica.
- O PDF normativo continua preservado e pode manter figuras históricas diferentes da implementação atual.
