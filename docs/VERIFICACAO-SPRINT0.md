# Verificação da Sprint 0 — primeira parte

## Complemento — 28/10/2026

- Os dez containers subiram saudáveis no Docker Desktop: Gateway, BFF, quatro serviços e quatro PostgreSQL.
- A consulta pública `/api/v1/ambiente` retornou todos os serviços `UP`.
- As migrações foram aplicadas em bancos reais, incluindo Frota V4.
- Shell e três microfrontends possuem builds separados e integração por contrato testada.
- As limitações abaixo descrevem somente a verificação histórica de 18/10/2026.

Data: 18/10/2026. Referência funcional: PDF `ArqCloud_PJBL - Completo.pdf` enviado pelo usuário.

## Resultados executados

- Build Maven `verify` dos seis projetos: **sucesso**.
- Runtime da validação final: JDK 21.0.12.1 portátil, baixado da Adoptium para `.tmp/toolchains/`. O Java padrão do Windows não foi substituído.
- Compilação com alvo Java 21.
- **31 testes passaram, zero falhas e zero erros**: 5 por serviço de domínio (20 no total), 8 no BFF e 3 no Gateway.
- ArchUnit verificou ausência de imports entre serviços; nos serviços/BFF, aplicação independente de frameworks/adaptadores e API sem acesso direto à persistência.
- Testes da consulta cobriram resposta saudável e indisponibilidade do banco por porta simulada.
- Testes do cliente HTTP do BFF cobriram contrato público, erro HTTP e resposta identificada como outro serviço.
- Teste HTTP do Gateway subiu o servidor real em porta aleatória e um upstream de teste: encaminhamento ao BFF e bloqueio da API interna de Frota passaram.
- `docker compose --env-file .env.sprint0.example -f compose.sprint0.yaml config --quiet`: **sucesso**.

## O que ainda não foi comprovado

O motor Docker não ficou disponível. O cliente retornou ausência do pipe `dockerDesktopLinuxEngine`; iniciar o aplicativo não disponibilizou o motor. Portanto, não foram executados o build das imagens, os quatro bancos, as migrações reais nem o teste ponta a ponta `scripts/Test-Sprint0.ps1`. A configuração válida do Compose não comprova execução dos contêineres.

O workflow GitHub foi criado, mas não executado remotamente. O diretório local não é um repositório Git inicializado.

O primeiro ensaio usou Java 26 e produziu avisos de bytecode no ArchUnit. Esse ensaio não é a evidência final: a validação foi repetida com Java 21 e concluída sem esses avisos. Há avisos de bibliotecas sobre hostname local, validação de configuração e carregamento dinâmico do agente de teste; não causaram falhas.

## Próxima verificação orientada

Abrir o Docker Desktop e confirmar que `docker version` mostra Client e Server. Depois seguir `tutorials/01-fundamentos.md`, executar o Compose, verificar a consulta agregada e realizar o exercício de falha parcial. A Sprint 0 completa também exige shell e microfrontends, ainda não construídos.
