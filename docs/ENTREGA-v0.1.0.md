# Verificação da entrega organizada

Data: 19/10/2026. Escopo: organização e formatação, sem evolução funcional.

## Antes e depois

A implementação original tinha 49 testes de backend aprovados, conforme relatórios locais e VERIFICACAO-SPRINT1.md. Na cópia organizada, o comando `scripts/Test-Project.ps1` executou o Maven Wrapper com Java 21 e repetiu os 49 testes sem falhas, compilando os seis serviços. Também reinstalou o frontend pelo lockfile, aprovou seus 8 testes e gerou o build TypeScript/Vite.

## Preservação

- Sete POMs comparados como XML: mesmo conteúdo, apenas formatação.
- Onze arquivos de recursos (configurações e migrações) e dois contratos OpenAPI comparados por SHA-256: iguais aos originais.
- Lockfile do frontend preservado, sem atualização das dependências da aplicação.
- Java formatado com google-java-format 1.25.2; frontend com Prettier 3.6.2.
- Compose validado estruturalmente com `config --quiet`.
- Workspace usa caminho relativo para ser portátil.

## Organização e versionamento

O pacote contém o código ativo, não o esqueleto antigo, temporários, senhas locais ou dependências baixadas. O histórico Git começa na importação desta base e registra depois a organização validada. Branch `main`, tag `v0.1.0`; nenhuma publicação remota. Os commits de preparação são de Codex, sem atribuição fictícia aos alunos.

## Limitações mantidas

Esta verificação não iniciou PostgreSQL/Docker nem validou as migrações em banco real. Também não concluiu login pela interface, perfis, cadastros ou microfrontends. A entrega não está liberada para produção e não equivale à conclusão da Sprint 1. Consulte PRONTO-PARA-SPRINT2.md antes de implementar operações.
