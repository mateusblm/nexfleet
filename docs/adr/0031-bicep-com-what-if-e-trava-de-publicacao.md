# ADR 0031 — Bicep com what-if e trava de publicação

Data: 08/11/2026. Estado: adotada para preparação; implantação não autorizada.

## Contexto

A Sprint 4 precisa transformar a arquitetura-alvo em infraestrutura reproduzível. A conta, região, moeda, cotas e orçamento ainda não foram conectados. Além disso, o transporte local é RabbitMQ, cujo binding para Azure Functions não é plenamente suportado em Flex Consumption.

Uma implantação antecipada poderia criar recursos pagos, escolher um plano caro para manter RabbitMQ ou publicar workloads sem conectividade de banco e segredos corretos.

## Decisão

- usar Bicep nativo para o primeiro ambiente `homolog`;
- compilar e lintar offline com uma versão fixa do Bicep e checksum;
- modelar a fundação gerenciada, orçamento e Function Flex sem publicar código;
- manter `publicationApproved=false` como padrão;
- não oferecer comando/script de implantação nesta versão;
- permitir somente `az deployment sub what-if` depois do preflight real e de autorização explícita no plano local;
- reprovar qualquer exclusão prevista pelo `what-if`;
- manter Container Apps como pendência até a migração Service Bus, rede e credenciais estarem implementadas.

O plano de exemplo nunca contém assinatura, senha ou autorização. Arquivos reais e relatórios ficam fora do Git.

## Consequências

- erros de sintaxe e propriedades são encontrados sem conta Azure;
- um deployment acidental usando os parâmetros padrão não modela recursos, pois a trava permanece falsa;
- a equipe consegue revisar nomes, SKUs e dependências antes do gasto;
- o modelo ainda não é implantável como aplicação completa;
- `what-if` conectado exigirá conta e permissões, embora não altere recursos;
- a migração para Service Bus torna-se requisito explícito da publicação econômica.

## Alternativas rejeitadas

- **Implantar diretamente pelo portal:** não deixa plano versionado nem revisão reproduzível.
- **Manter RabbitMQ e usar Function Premium/Dedicated:** aumenta custo antes de medir a necessidade.
- **Declarar Container Apps com imagens fictícias:** gera um plano enganoso e não executável.
- **Guardar senhas em arquivo de parâmetros:** expõe credenciais e histórico local desnecessariamente.
