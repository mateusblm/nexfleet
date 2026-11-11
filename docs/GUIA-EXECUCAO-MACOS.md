# Guia de execução do NexFleet no macOS

Este guia executa o mesmo ambiente local do Windows: backend e bancos em contêineres Docker, com shell e três microfrontends React executados pelo Node.js no Mac.

## 1. O que muda no MacBook

- use `pwsh` no lugar de `powershell.exe`;
- use `npm` no lugar de `npm.cmd`;
- não execute `Install-Dependencies.ps1`, pois o instalador portátil atual baixa binários Windows;
- instale Node.js 24 e PowerShell 7 diretamente no macOS;
- os dados continuam nos volumes Docker, não em um PostgreSQL instalado no Mac.

## 2. Pré-requisitos

Instale:

1. [Docker Desktop para Mac](https://docs.docker.com/desktop/setup/install/mac-install/), escolhendo Apple Silicon ou Intel corretamente;
2. [Node.js 24 LTS](https://nodejs.org/en/download) pelo instalador oficial;
3. [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/install-powershell-on-macos) pelo pacote oficial da Microsoft;
4. VS Code, opcionalmente.

Para testes Java no host, instale também um JDK 21. Para validar Bicep manualmente:

```bash
brew tap azure/bicep
brew install bicep
```

Confirme no Terminal:

```bash
docker version
docker compose version
node --version
npm --version
pwsh --version
```

O Docker Desktop deve estar aberto e mostrar o engine em execução. O Node deve estar na versão principal 24.

## 3. Entrar na pasta

Exemplo para um projeto em Downloads:

```bash
cd "$HOME/Downloads/NexFleet-v0.14.0"
pwd
```

Os comandos seguintes devem ser executados na pasta que contém `compose.sprint0.yaml`.

## 4. Instalar dependências frontend

```bash
(cd frontend && npm ci)
(cd microfrontends/frota && npm ci)
(cd microfrontends/operacoes && npm ci)
(cd microfrontends/painel && npm ci)
```

O backend baixa suas dependências durante o build Docker. Não é necessário instalar Maven para simplesmente subir o ambiente.

## 5. Criar configuração e segredos locais

```bash
pwsh ./scripts/Initialize-Local.ps1
```

Abra `.env.sprint0` e substitua somente o valor de `LOCAL_USER_PASSWORD` por uma senha local forte:

```bash
nano .env.sprint0
```

Salve com `Ctrl+O`, confirme com Enter e saia com `Ctrl+X`. Não publique `.env.sprint0` nem a pasta `.secrets`.

## 6. Primeira subida do backend

```bash
pwsh ./scripts/Start-Local.ps1 -ProvisionUser
```

Esse comando:

1. constrói as imagens Java e da Function;
2. inicia cinco PostgreSQL, RabbitMQ, Azurite e Prometheus;
3. inicia Gateway, BFF e os quatro microsserviços;
4. cria o primeiro Administrador local;
5. executa verificações de saúde, mensageria e observabilidade.

Na rotina diária, use:

```bash
pwsh ./scripts/Start-Local.ps1 -NoBuild
```

Remova `-NoBuild` quando alterar Java, Dockerfile ou dependências do backend.

## 7. Subir a interface

Abra quatro terminais, todos na raiz do projeto.

Terminal 1 — shell:

```bash
cd frontend
npm run dev
```

Terminal 2 — Frota:

```bash
cd microfrontends/frota
npm run dev
```

Terminal 3 — Operações:

```bash
cd microfrontends/operacoes
npm run dev
```

Terminal 4 — Painel:

```bash
cd microfrontends/painel
npm run dev
```

Abra `http://127.0.0.1:5173`. O usuário está em `LOCAL_USER_EMAIL` e a senha é o valor definido em `LOCAL_USER_PASSWORD` no `.env.sprint0`.

## 8. Endereços locais

| Componente | Endereço |
|---|---|
| NexFleet | `http://127.0.0.1:5173` |
| Gateway | `http://127.0.0.1:8080` |
| RabbitMQ | `http://127.0.0.1:15672` |
| Prometheus | `http://127.0.0.1:9090` |

## 9. Acessar o banco pelo Terminal

Use o nome do serviço Compose para não depender do nome físico do contêiner:

```bash
docker compose \
  --env-file .env.sprint0 \
  -f compose.sprint0.yaml \
  exec frota-db psql -U frota -d frota
```

No prompt `frota=#`:

```sql
SET search_path TO frota;
\dt
SELECT * FROM veiculo ORDER BY criado_em DESC LIMIT 20;
\q
```

## 10. Parar sem apagar os dados

Nos quatro terminais frontend, pressione `Ctrl+C`. Depois:

```bash
pwsh ./scripts/Stop-Local.ps1
```

Os volumes PostgreSQL são preservados. Não acrescente `--volumes` se deseja manter os cadastros.

## 11. Solução rápida de problemas

- `pwsh: command not found`: instale/reabra o Terminal após instalar PowerShell 7.
- `docker daemon is not running`: abra Docker Desktop e aguarde o engine.
- `npm: command not found`: reinstale Node.js 24 e reabra o Terminal.
- porta ocupada: execute `lsof -nP -iTCP:5173 -sTCP:LISTEN` ou substitua a porta consultada.
- microfrontend indisponível: confirme que os quatro comandos `npm run dev` continuam ativos.
- arquitetura Apple Silicon: use Docker Desktop e Node para `arm64`; as imagens Linux usadas pelo projeto oferecem suporte compatível.

## 12. Azure é opcional para execução local

O login Azure, o Bicep e o `what-if` pertencem à publicação da Sprint 4. O projeto local funciona completamente sem criar recursos Azure.
