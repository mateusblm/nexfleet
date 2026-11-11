# Aula 4 — O login chega à interface

## O resultado

Agora a tela oferece e-mail, senha, entrar, verificar sessão e sair. Antes, apenas Identidade sabia autenticar; agora conectamos essa funcionalidade à interface sem permitir que o navegador acesse serviços internos diretamente.

## O que acontece quando você entra

1. `Login.tsx` coleta os campos e pede a `auth.ts` que envie um POST.
2. `/api/v1/auth/login` passa pelo proxy local do Vite e chega ao Gateway.
3. Gateway aceita essa combinação específica de caminho e método e encaminha para o BFF.
4. A fatia `bff/autenticar` valida a estrutura da entrada. Seu adaptador HTTP chama a API de Identidade.
5. Identidade verifica conta ativa/senha e emite o JWT como já estudamos na Aula 3.
6. A tela recebe o token e chama `/api/v1/auth/me`, enviando `Authorization: Bearer <token>`.
7. BFF encaminha o Bearer a Identidade. Só após a confirmação, a interface mostra o identificador autenticado.

**Gateway não declara o token válido.** O BFF também não tenta interpretar sua assinatura: consulta Identidade, a autoridade que já tem a chave. Permitir o encaminhamento de `/me` no filtro do BFF não significa permitir leitura sem autenticação: o caso de uso exige Bearer e a resposta depende da validação em Identidade.

## Por que não guardamos o token no navegador?

O estado React mantém o token apenas na memória da página, evitando persistência automática em localStorage/sessionStorage. Atualizar a página ou clicar em sair elimina essa sessão local. Isso não elimina riscos de XSS, não revoga um token já emitido no servidor e ainda não é a estratégia final de produção. A senha digitada é limpa após a tentativa.

O prazo do token também agenda a saída da tela. A validação definitiva continua sendo do backend; o relógio do navegador não é uma proteção de segurança.

## Responsabilidade de cada arquivo

- `frontend/src/Login.tsx`: apresentação, campos e estado.
- `frontend/src/auth.ts`: chamadas HTTP e validação das respostas.
- `services/bff/.../autenticar/application`: validação de entrada e portas, sem Spring.
- `services/bff/.../autenticar/infrastructure/HttpIdentidade.java`: comunicação com timeout e tratamento de falhas, sem expor corpos de erro internos.
- `services/bff/.../autenticar/api/AuthController.java`: contrato HTTP com respostas sem cache.
- `services/gateway/.../GatewayConfig.java`: duas novas rotas explícitas; as APIs internas permanecem bloqueadas.

## Como experimentar

1. Abra o workspace da pasta de desenvolvimento **Downloads/NexFleet**. Os ZIPs versionados são entregas, não outras pastas para editar em paralelo.
2. Configure o JDK 21 e prepare `.env.sprint0` seguindo a Aula 3, com senhas próprias e JWT_SECRET.
3. Com Docker Desktop ativo, siga o seed local opcional da Aula 3 para provisionar sua conta. Não existe usuário/senha padrão.
4. Suba o ambiente e execute `npm.cmd ci` e `npm.cmd run dev` dentro de `frontend`.
5. Abra http://127.0.0.1:5173 e entre usando a conta provisionada.
6. Clique em verificar sessão, saia e tente uma senha incorreta. Atualize a página e confirme que o login não foi persistido.

Se o Docker estiver indisponível, a tela abre e mostra erro ao tentar entrar; não há sucesso simulado na aplicação. Os simuladores existem somente nos testes.

## Testar e interpretar

Na raiz, `./scripts/Test-Project.ps1` testa backend e interface. Os testes HTTP executam servidores reais de BFF/Gateway com respostas controladas do próximo serviço; os de interface usam jsdom. Isso não prova o fluxo completo com PostgreSQL real e não equivale a uma inspeção visual em navegador.

401 significa credenciais/sessão inválidas; indisponibilidade do serviço é 503 no BFF. Não usamos mensagens internas para revelar se um e-mail está cadastrado.

## O que continua pendente

Perfis/autorização, cadastros de Frota, microfrontends, rate limiting, revogação/refresh e validação ponta a ponta com banco real. A assinatura assimétrica permanece planejada antes de os outros microsserviços passarem a validar tokens por conta própria. Nesta etapa, apenas Identidade valida e possui a chave.

**Exercício:** explique por que receber um token não faz a tela mostrar sucesso imediatamente: ainda confirmamos `/me`. Depois localize onde o erro 401 faz a interface voltar ao formulário.
