# ADR 0012 — Contrato de integração dos microfrontends

- Status: aceito
- Data: 28/10/2026

## Contexto

O PJBL exige um shell e três microfrontends React/TypeScript/Vite implantáveis separadamente. A interface anterior reunia autenticação, usuários e toda a Frota no mesmo build. Adotar um framework adicional de federação aumentaria dependências e configuração sem ser necessário para o escopo acadêmico atual.

## Decisão

O shell permanece em `frontend`. Frota, Operações e Painel ficam em projetos próprios sob `microfrontends`, cada um com dependências travadas, testes, build e porta local. Cada remoto exporta:

```ts
mount(container, { token, perfil }): () => void
```

O shell importa o módulo ES pela URL configurada, monta-o em um elemento dedicado e chama a função de desmontagem ao trocar de área, sessão ou versão. Em desenvolvimento, as URLs apontam para as portas 5174–5176. Na publicação, apontam para `remoteEntry.js` em origens ou caminhos configurados. O CSS de produção acompanha o módulo com o mesmo nome-base.

Quando os remotos estiverem em origens diferentes, a hospedagem deve permitir CORS somente para as origens previstas e a política CSP do shell deve listar explicitamente esses endereços. Essa configuração faz parte da publicação da Sprint 4.

O token permanece somente em memória e é entregue ao remoto como propriedade; não vai para URL, armazenamento local ou variável global. APIs continuam passando por Gateway e BFF. O shell é responsável por login, sessão, navegação e administração de usuários; o MFE de Frota possui veículos, motoristas e vínculos.

## Consequências

- Cada área pode compilar e ser publicada sem recompilar o código-fonte das demais.
- Falha de um remoto produz mensagem localizada e não derruba login nem o shell.
- React é incluído em cada bundle nesta primeira versão, aumentando o tamanho, mas preservando independência e evitando acoplamento de versões.
- O contrato é pequeno e testável, mas alterações incompatíveis exigirão versionamento coordenado.
- Operações e Painel não simulam regras ainda inexistentes; recebem implementação nas Sprints 2 e 3.

## Rollback

O shell pode voltar à v0.6.0 sem alteração de banco. Os diretórios dos remotos são aditivos e não interferem nos serviços Java ou nas migrações.
