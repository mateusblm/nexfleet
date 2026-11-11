# Aula 11 — Shell e microfrontends

## O que foi construído

A interface deixou de ser um único pacote. Agora existem quatro aplicações:

- `frontend`: shell, login, sessão, navegação e usuários;
- `microfrontends/frota`: veículos, motoristas e vínculos;
- `microfrontends/operacoes`: estrutura da Sprint 2;
- `microfrontends/painel`: estrutura da Sprint 3.

Cada pasta possui seu próprio `package.json`, `package-lock.json`, testes e build. Isso é o que torna os microfrontends unidades implantáveis, e não apenas componentes React em pastas diferentes.

## Por que usar

Um microfrontend permite que uma área evolua e seja publicada separadamente. É útil quando domínios e equipes têm ciclos próprios. O custo é operacional: há mais builds, URLs, compatibilidade e tratamento de indisponibilidade. Por isso o contrato de integração foi mantido pequeno.

## Como funciona

Cada remoto exporta uma função `mount`. O shell fornece um elemento HTML, o token em memória e o perfil. O remoto renderiza dentro desse elemento e devolve uma função `unmount`. Quando o usuário fecha a área ou sai, o shell desmonta a árvore React e remove o CSS remoto.

O shell conhece somente a URL e o contrato; ele não importa `Veiculos.tsx`, `Motoristas.tsx` ou `Vinculos.tsx`. Em desenvolvimento, as URLs padrão são:

| Aplicação | Porta |
|---|---:|
| Shell | 5173 |
| Frota | 5174 |
| Operações | 5175 |
| Painel | 5176 |

Para mudar uma origem sem recompilar o código-fonte, configure `VITE_MFE_FROTA_URL`, `VITE_MFE_OPERACOES_URL` ou `VITE_MFE_PAINEL_URL` antes do build do shell.

No ambiente publicado, a origem dos arquivos remotos precisa permitir CORS para o shell e deve aparecer na política CSP. Não use `*` em produção apenas para contornar erro de carregamento.

## Como executar

Abra quatro terminais. Em cada pasta, rode `npm.cmd ci` na primeira vez e depois `npm.cmd run dev`. Inicie os três MFEs e por último o shell. O backend continua entrando somente pelo Gateway em `127.0.0.1:8080`.

O modo isolado de Frota serve para conferir carregamento e aparência, mas não cria sessão real. Para usar as APIs, abra o shell, faça login e selecione Frota.

## Como testar

`./scripts/Test-Project.ps1` executa backend, shell e os três MFEs. O host testa montagem, falha remota e desmontagem. Frota mantém os testes dos três cadastros. Operações e Painel testam que não apresentam dados fictícios antes de suas sprints.

## Quando não usar

Não separe uma tela pequena apenas por moda. Se todos os módulos sempre mudam e publicam juntos, um frontend único costuma ser mais simples. No NexFleet, a separação existe porque é requisito arquitetural e acompanha os domínios Frota, Operações e Indicadores.
