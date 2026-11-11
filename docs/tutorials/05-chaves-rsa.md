# Aula 5 — Quem pode criar e quem pode verificar um login?

## O que construímos

O login retorna um JWT: um comprovante temporário de autenticação. Ele é assinado, não criptografado. Quem recebe um token pode ler seu conteúdo; por isso não colocamos senha ou dados pessoais nele.

Até agora, Identidade usa HS256: o mesmo segredo serve para assinar e conferir a assinatura. Funciona no estudo local, mas não devemos entregar esse segredo a todos os microsserviços.

Adicionamos um modo RSA, chamado `jwt-rsa`, com duas partes:

- **Chave privada:** fica somente em Identidade e assina os tokens.
- **Chave pública:** permite conferir a assinatura sem dar a capacidade de emitir tokens.

Pense em um emissor que tem o instrumento para assinar documentos e em verificadores que só conseguem conferir essa assinatura. A verificação ainda precisa conferir o emissor, o destinatário esperado (`audience`) e a expiração.

## Onde isso aparece no código

- `RsaJwtConfig`: lê a chave externa, prepara assinatura e validação.
- `JwtEmitirToken`: mantém o mesmo conteúdo do token, mas recebe o cabeçalho RS256 e o identificador da chave (`kid`).
- `JwksController`: disponibiliza um conjunto de chaves públicas, chamado JWKS.
- `SecurityConfig`: permite consultar esse endereço dentro da rede dos serviços, sem exigir login.

O caso de uso `Autenticar` não muda. Ele conhece a interface `EmitirToken`, não os detalhes do algoritmo. Isso é Clean Architecture em prática: mudar infraestrutura sem reescrever a regra de login. A funcionalidade continua organizada na fatia `autenticar`.

## Como experimentar

Pré-requisitos: PowerShell 7, Docker funcionando e `.env.sprint0` configurado conforme as aulas anteriores. Execute a partir da raiz do projeto.

1. Gere uma chave **uma única vez**:

```powershell
./scripts/New-LocalJwtKey.ps1
```

O arquivo fica em `.secrets/identidade-jwt.pem`, ignorado pelo Git. Não o coloque no ZIP, em mensagens ou em repositórios. Restrinja o acesso ao seu usuário; o gerador não configura permissões do sistema operacional. Não apague ou gere outra chave a cada inicialização.

2. Para uma conta já criada, ative RSA:

```powershell
docker compose --env-file .env.sprint0 -f compose.sprint0.yaml -f compose.jwt-rsa.yaml up --build -d
```

O Compose base ainda pede `JWT_SECRET`; mantenha o valor existente. O aplicativo RSA não o utiliza. A chave privada é montada somente no contêiner de Identidade, em modo de leitura.

3. Se ainda precisar provisionar a conta de estudo, configure `LOCAL_USER_EMAIL` e `LOCAL_USER_PASSWORD` como na aula 3 e combine os perfis:

```powershell
$env:IDENTIDADE_PROFILES = 'local-seed,jwt-rsa'
docker compose --env-file .env.sprint0 -f compose.sprint0.yaml -f compose.sprint1-local.yaml -f compose.jwt-rsa.yaml up --build -d
Remove-Item Env:IDENTIDADE_PROFILES
```

Após provisionar, execute novamente o comando do passo 2, sem o override de seed. Isso recria Identidade sem o provisionamento ativado.

4. Inicie o frontend conforme a aula 4 e faça **novo login**. Na interface o uso permanece igual. O formato de resposta também permanece igual.

5. Para consultar apenas a chave pública dentro da rede local:

```powershell
docker compose --env-file .env.sprint0 -f compose.sprint0.yaml -f compose.jwt-rsa.yaml exec identidade curl -fsS http://localhost:8080/.well-known/jwks.json
```

Você verá `kty`, `kid`, `alg`, `n` e `e`. Nunca devem aparecer `d`, `p` ou `q`, que pertencem à parte privada. Esse endpoint não foi exposto pelo Gateway.

## Quando usar e como voltar atrás

Use este modo antes de implementar verificação independente nos outros serviços. Por enquanto, BFF ainda consulta Identidade: não afirmamos que a validação distribuída esteja pronta.

A troca entre HMAC e RSA encerra a validade das sessões do modo anterior. Faça isso em ambiente local sem usuários ativos e depois entre novamente. Não misture réplicas dos dois modos.

Para voltar ao modo anterior, execute o Compose sem `compose.jwt-rsa.yaml`, mantendo o segredo HMAC original. O banco não muda; um novo login é necessário. Não remova volumes e não rode `down -v`.

## O que os testes comprovam

Os testes verificam assinatura pública, recusa de assinatura de outra chave, algoritmo antigo, expiração, emissor/audiência inválidos, arquivo inválido e chave fraca. Testes HTTP verificam o perfil RSA sem segredo HMAC, o contrato de login, `/me` e ausência de componentes privados no JWKS. Os testes anteriores preservam a prova do modo legado.

Isso não substitui a integração com PostgreSQL real, nem comprova publicação em Azure. Rotação automática, permissões de usuário e revogação não foram implementadas.

Para aprofundar: [documentação oficial do Spring Security](https://docs.spring.io/spring-security/reference/servlet/oauth2/resource-server/jwt.html).
