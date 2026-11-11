# Aula 3 — Sprint 1: autenticação no serviço Identidade

Esta aula registra a primeira etapa, v0.1.0. Na v0.2.0 o login foi conectado à interface via Gateway/BFF; continue pela [Aula 4](04-login-integrado.md). As instruções de chave JWT e conta local desta aula continuam necessárias.

## O que foi implementado

Esta é a primeira parte da Sprint 1, não a sprint inteira. Temos a API interna de login, verificação BCrypt, emissão e validação de JWT e consulta do identificador autenticado. Gateway/BFF e a tela ainda não encaminham o login. Não existem permissões por perfil nem cadastros de Frota nesta etapa.

## Quatro conceitos importantes

1. **Autenticação:** confirmar quem é a pessoa. E-mail e senha são conferidos pelo serviço Identidade.
2. **Autorização:** decidir o que essa pessoa pode fazer. Estar autenticado não dá automaticamente permissão de administrador. A matriz de perfis será implementada separadamente.
3. **BCrypt:** transformação de mão única. O banco guarda um hash, não a senha original. A mesma senha pode gerar hashes diferentes porque há um valor aleatório chamado salt. Para verificar, usamos `matches`, não comparamos dois hashes gerados separadamente.
4. **JWT:** token assinado com identificador, emissor, público-alvo e validade. A assinatura permite detectar alterações. O conteúdo não é secreto nem criptografado; por isso não colocamos senha ou e-mail nele.

Referência técnica: https://docs.spring.io/spring-security/reference/features/authentication/password-storage.html.

## Percorra o código nesta ordem

1. `services/identidade/src/main/java/br/com/nexfleet/identidade/autenticar/api/LoginController.java`: recebe o JSON HTTP.
2. `autenticar/application/Autenticar.java`: normaliza e-mail, busca o usuário, confere senha/conta ativa e só então solicita um token.
3. `autenticar/application/BuscarUsuario.java`, `VerificarSenha.java` e `EmitirToken.java`: contratos necessários à regra, chamados portas.
4. `autenticar/infrastructure/`: implementações das portas usando JDBC, BCrypt e JWT.
5. `config/AuthConfig.java`: conecta as implementações aos contratos.
6. `config/SecurityConfig.java`: login público, `/me` autenticado e demais caminhos não previstos bloqueados.

Isso combina **Vertical Slice** (arquivos agrupados pela funcionalidade `autenticar`) com **Clean Architecture** (a regra não importa banco, Spring ou JWT). Quando trocarmos um detalhe técnico, a regra central não precisa conhecer a troca.

## Contrato interno

`POST /api/v1/identidade/login` recebe `{ "email": "seu-email", "senha": "sua-senha" }`.

- Sucesso: HTTP 200 com `accessToken`, `tokenType: Bearer` e `expiresIn: 900`.
- Credenciais incorretas, conta ausente ou inativa: HTTP 401 com a mesma mensagem genérica, sem revelar a existência da conta.
- JSON malformado: HTTP 400.
- Falha de banco ou configuração: não é sucesso de autenticação.

`GET /api/v1/identidade/me` exige o cabeçalho `Authorization: Bearer <token>` e responde com o ID. Sem token ou com assinatura, validade, emissor ou público-alvo inválidos, retorna 401. Uma rota proibida pode retornar 403 para um usuário autenticado.

O token dura 15 minutos. Não há renovação ou revogação imediata: uma conta desativada não recebe novos tokens, mas um token já emitido pode continuar válido até expirar. Não publique este estágio na internet: limitação de tentativas, gestão de contas, perfis e política de revogação ainda estão pendentes.

## Configuração obrigatória nova

A partir desta etapa, Identidade exige `JWT_SECRET`. Antes de iniciar o ambiente, gere uma chave no PowerShell:

```powershell
$jwtBytes = New-Object byte[] 32
[System.Security.Cryptography.RandomNumberGenerator]::Fill($jwtBytes)
[Convert]::ToBase64String($jwtBytes)
```

Copie o resultado para `JWT_SECRET=` no seu `.env.sprint0`, mantendo as quatro senhas de banco existentes. Não copie o arquivo de exemplo por cima do seu arquivo configurado. Não envie a chave no chat, não coloque no Git nem no frontend. O marcador do exemplo é inválido de propósito. A aplicação falha ao iniciar se a chave estiver ausente ou for curta/inválida.

HS256 é uma decisão provisória e restrita a este serviço no estudo local. Não distribuiremos a chave de assinatura aos outros serviços indiscriminadamente: antes de integrar a verificação distribuída, adotaremos assinatura assimétrica e distribuição da chave pública. Isso evita que cada verificador também possa emitir tokens.

## Criar uma conta de estudo local

Não há usuário ou senha padrão. O perfil opcional `local-seed` cria uma conta sem privilégios de perfil, exclusivamente para estudo. No terminal, defina seu e-mail e leia a senha sem exibi-la:

```powershell
$env:LOCAL_USER_EMAIL = Read-Host 'E-mail da conta de estudo'
$senhaLocal = Read-Host 'Senha: mínimo 12 caracteres, máximo 72 bytes UTF-8' -AsSecureString
$env:LOCAL_USER_PASSWORD = [System.Net.NetworkCredential]::new('', $senhaLocal).Password
try {
  docker compose --env-file .env.sprint0 -f compose.sprint0.yaml -f compose.sprint1-local.yaml up --build -d --wait
} finally {
  Remove-Item Env:LOCAL_USER_PASSWORD -ErrorAction SilentlyContinue
  Remove-Item Env:LOCAL_USER_EMAIL -ErrorAction SilentlyContinue
}
```

A senha existe temporariamente nas variáveis do processo e fica na configuração local do contêiner de seed; esse mecanismo não é para produção. Depois da criação, recrie apenas Identidade sem o override, para remover essas variáveis do contêiner:

```powershell
docker compose --env-file .env.sprint0 -f compose.sprint0.yaml up -d --force-recreate identidade
```

Repetir o seed não troca a senha nem reativa contas existentes. Para um futuro fluxo administrativo, criaremos uma API própria com autorização e auditoria. Nunca habilite `local-seed` na Azure.

## Banco e migração segura

Flyway aplica `V2__criar_usuarios.sql` depois de V1. A nova tabela pertence apenas ao banco Identidade. O e-mail normalizado é único; a senha deve ter formato BCrypt.

É uma expansão: não apaga nem modifica tabelas existentes. A versão anterior do aplicativo pode voltar a executar deixando a tabela adicional no banco. Não apague a tabela, não edite V1/V2 já aplicadas e não remova volumes para fazer rollback. Antes de publicar, precisamos comprovar a migração com PostgreSQL real, incluindo duplicidade e preservação de contas.

## Como estudar e testar agora

Com JDK 21 e Maven disponíveis:

```powershell
mvn -f services/identidade/pom.xml verify
```

Os testes exercitam regra de autenticação, criptografia real, filtro HTTP e arquitetura. O repositório de usuários é simulado nos testes HTTP: eles não substituem validação do PostgreSQL e do caminho navegador → Gateway → BFF → Identidade.

Exercício: leia `Autenticar.executar` e explique por que não emitimos o token antes de verificar `ativo` e a senha. Depois compare 401 (não autenticado) e 403 (acesso proibido). O próximo passo será integrar login pelo Gateway/BFF e criar a tela, junto com a evolução para chaves assimétricas; depois avançaremos para os cadastros de Frota.
