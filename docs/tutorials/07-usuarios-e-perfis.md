# Aula 7 — Administrador e Gestor de Frota

## O que agora existe

Um Administrador pode cadastrar, listar, editar e desativar contas. Um Gestor não pode gerenciar usuários. Isso implementa a distinção do RF02/RF03 do PJBL, sem criar um terceiro perfil de motorista.

O token identifica a pessoa e o perfil concedido no login. Esse é o ponto de partida, mas o backend consulta também se o Administrador continua ativo. A interface esconder um botão não impede uma chamada feita fora dela; por isso a proteção precisa existir no servidor.

## Como o fluxo funciona

1. A tela envia JSON e Bearer ao Gateway.
2. Gateway encaminha ao BFF, que usa o contrato de Identidade.
3. Spring Security valida o token e exige perfil administrativo.
4. `GerenciarUsuarios` verifica a conta ativa, valida os campos e usa a porta `Usuarios`.
5. `JdbcUsuarios` executa SQL somente no banco de Identidade.
6. O retorno contém ID, e-mail, perfil e estado; nunca senha ou hash.

Clean Architecture aparece na separação: o caso de uso não importa Spring ou JDBC. O adaptador de banco implementa uma interface. Vertical Slice reúne a funcionalidade em `gerenciarusuarios`, em vez de misturar seus arquivos com os cadastros futuros de Frota.

## Preparar uma conta administrativa local

Pré-requisitos: Docker funcionando, arquivo `.env.sprint0` configurado e, para RSA, a chave da Aula 5. A migração V3 será aplicada ao iniciar Identidade. Faça backup antes de atualizar um ambiente com dados importantes; não apague volumes.

No arquivo `.env.sprint0`, configure os campos de seed da Aula 3 e acrescente:

```dotenv
LOCAL_USER_PROFILE=ADMINISTRADOR
```

Use um **e-mail novo** em `LOCAL_USER_EMAIL` e uma senha própria em `LOCAL_USER_PASSWORD`. Esses valores não devem ir para Git nem para mensagens. A senha deve ter pelo menos 12 caracteres e no máximo 72 bytes UTF-8.

O seed não altera contas existentes. Se usar o e-mail de um Gestor já cadastrado, ele continuará Gestor; isso é uma proteção contra promoção silenciosa. Contas antigas também recebem GESTOR_FROTA na migração.

Na raiz do projeto, para executar com RSA:

```powershell
$env:IDENTIDADE_PROFILES = 'local-seed,jwt-rsa'
docker compose --env-file .env.sprint0 -f compose.sprint0.yaml -f compose.sprint1-local.yaml -f compose.jwt-rsa.yaml up --build -d
Remove-Item Env:IDENTIDADE_PROFILES
```

Depois de provisionar, recrie o ambiente sem seed:

```powershell
docker compose --env-file .env.sprint0 -f compose.sprint0.yaml -f compose.jwt-rsa.yaml up --build -d
```

O modo HMAC de estudo também suporta perfis: use somente o Compose base e o override de seed, sem o override RSA. Na Azure o seed local não deve ser habilitado.

## Usar a tela

Abra o frontend conforme a Aula 4, faça novo login com o Administrador e clique em **Gerenciar usuários**. O painel permite:

- Cadastrar uma conta com perfil escolhido e senha inicial.
- Consultar a lista em páginas de 20 contas.
- Editar e-mail, perfil e estado ativo, preservando a senha.
- Desativar após confirmação, sem apagar o registro.

E-mail duplicado retorna 409; campos inválidos retornam 422; conta inexistente retorna 404; falta de sessão retorna 401; falta de permissão retorna 403. A tela mantém os campos não secretos para correção e limpa a senha após a tentativa de cadastro.

Não desative nem rebaixe a última conta administrativa. Essa política ainda precisa ser formalizada antes da publicação. Desativar impede novos logins; nesta funcionalidade, o bloqueio administrativo também considera o estado atual no banco. Outros acessos baseados apenas no JWT ainda podem durar até sua expiração de 15 minutos.

## O que foi testado e o que falta

Testes de aplicação e HTTP cobrem autorização, revogação administrativa por estado atual, criação com BCrypt, consulta, edição, desativação, erros e paginação. Testes de Gateway/BFF verificam encaminhamento de método/Bearer e respostas controladas. Testes React verificam os formulários e a confirmação de desativação.

Os testes de API usam portas simuladas; não demonstram aplicação da migração nem unicidade real no PostgreSQL. O ambiente completo ainda precisa subir com Docker. Esta entrega não conclui todas as sprints nem substitui os MFEs de Frota, Operações e Painel que faltam.
