# Aula 28 — diagramas que acompanham o código

## 1. Por que revisar os diagramas

Um diagrama arquitetural é útil quando explica o sistema que realmente executa. O PDF do PJBL descreveu a solução-alvo antes de todas as fatias existirem. Depois da implementação, nomes de classes, tabelas e detalhes técnicos precisam ser confrontados com o repositório.

A revisão da v0.24.0 encontrou um exemplo concreto: o desenho inicial previa um pacote `domain` e JPA para Registrar Abastecimento, enquanto o código atual usa portas em `application` e adaptadores JDBC em `infrastructure`.

## 2. Como ler os quatro níveis C4

No arquivo `docs/DIAGRAMAS-ARQUITETURA.md`:

1. O nível 1 mostra pessoas, o NexFleet e a integração externa ainda futura.
2. O nível 2 abre o NexFleet em shell, microfrontends, Gateway, BFF, serviços, broker, Function e bancos.
3. O nível 3 abre o serviço Operações em API, aplicação, portas e adaptadores.
4. O nível 4 mostra as classes e dependências da fatia Registrar Abastecimento.

Cada nível responde a uma pergunta diferente. Não é necessário colocar todas as classes no contexto nem todos os bancos no diagrama de classes.

## 3. Como ler as sequências

A sequência de abastecimento separa duas fases:

- antes do `201`, Operações valida Frota e confirma uma transação local;
- depois do commit, o job publica o evento e os consumidores trabalham de forma assíncrona.

Essa ordem explica por que uma falha do RabbitMQ não desfaz o abastecimento já confirmado. A sequência de rejeição mostra que a regressão do hodômetro causa `422` e rollback antes de qualquer efeito permanente.

## 4. Por que existem cinco DERs físicos

Database per Service impede uma FK entre bancos. Por isso, `veiculo_id` em Operações é um UUID de referência, não uma FK para `frota.veiculo`.

Somente o banco de Frota possui FKs físicas de veículo e motorista para `frota.veiculo_motorista`. Operações protege relações por transação e regra de aplicação; Indicadores e Notificações usam `evento_id` para idempotência.

## 5. Como a documentação é verificada

Execute na raiz:

```powershell
./scripts/Test-Project.ps1 -SkipInstall
```

O módulo `quality` lê as migrações SQL, encontra cada `CREATE TABLE` e exige as onze tabelas no inventário DER. Também confirma a presença dos quatro níveis C4, das seções UML e das classes centrais do fluxo.

Isso detecta divergências estruturais, mas não decide se uma seta está semanticamente correta. A revisão humana continua obrigatória.

## 6. Quando atualizar

Atualize os diagramas na mesma entrega que alterar:

- uma rota pública ou interna;
- uma fronteira de serviço;
- uma classe central do fluxo;
- um evento ou consumidor;
- uma migração Flyway;
- uma decisão entre implementação local e Azure futura.

O PDF normativo não deve ser sobrescrito. A visão corrente fica no Markdown versionado e a justificativa está na ADR 0029.
