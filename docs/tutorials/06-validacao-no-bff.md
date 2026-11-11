# Aula 6 — Verificar antes de encaminhar

## O que mudou

Na aula anterior, Identidade passou a oferecer uma chave pública. Agora o BFF sabe usá-la para verificar tokens quando o perfil RSA está ativo. Esse é o primeiro consumidor da chave pública em outro serviço.

O caminho de consulta da sessão fica assim:

1. A interface envia o token ao Gateway.
2. O Gateway encaminha ao BFF, sem verificar a assinatura nesta etapa.
3. O BFF consulta o JWKS quando necessário e confere assinatura, algoritmo, emissor, audiência e prazo.
4. Se a verificação falhar, o BFF bloqueia o acesso antes de chamar `/me` de Identidade.
5. Se passar, a consulta segue a Identidade, mantendo o comportamento da aula anterior.

As chaves públicas podem ser reutilizadas do cache da biblioteca. Isso evita baixá-las a cada requisição. A consulta de sessão ainda depende de Identidade, pois não removemos seu encaminhamento.

## Por que fazer isso?

Cada serviço precisa proteger a própria entrada. Não basta confiar que a interface escondeu um botão ou que a requisição passou pelo Gateway. Quando implementarmos os cadastros, seus serviços também precisarão verificar quem chamou e o que essa pessoa pode fazer.

**Autenticação** confirma a identidade representada pelo token. **Autorização** decide se essa identidade pode executar a operação. Esta aula cuida apenas da primeira. A ADR 0002 já define Administrador e Gestor de Frota; a aplicação efetiva dessas permissões ainda está pendente.

O BFF recebe apenas a chave pública. Mesmo que um serviço verificador seja comprometido, essa chave não permite assinar novos tokens. Ela também não protege tokens roubados: HTTPS e tratamento seguro dos tokens continuam necessários.

## Como implementamos

- Acrescentamos a dependência Resource Server ao BFF, sem criar um filtro JWT manual.
- `config/JwksConfig.java` configura o endereço das chaves, RS256, emissor, audiência e prazo obrigatório.
- `config/SecurityConfig.java` exige autenticação em `/api/v1/auth/me` quando `jwt-rsa` está ativo.
- Login continua público. Rotas não autorizadas continuam bloqueadas.
- O caso de uso de autenticação e o cliente HTTP de Identidade não foram reescritos.

Se a consulta das chaves falhar e não houver chave utilizável, o acesso não é liberado. Não há retorno automático ao modo antigo.

## Como executar

Use a chave e o arquivo de ambiente da Aula 5. Na raiz do projeto:

```powershell
docker compose --env-file .env.sprint0 -f compose.sprint0.yaml -f compose.jwt-rsa.yaml up --build -d
```

O override agora ativa RSA em **Identidade e BFF**. A chave privada continua montada somente em Identidade. Não é necessário gerar outra chave.

Inicie o frontend como na Aula 4 e entre novamente. O token continua somente na memória da interface. A aparência da tela não mudou: esta é uma melhoria do backend.

Para testar a recusa de um token inválido, sem usar uma senha:

```powershell
curl.exe -i -H "Authorization: Bearer invalido" http://127.0.0.1:8080/api/v1/auth/me
```

O resultado esperado é `401`. Não cole tokens reais em mensagens ou capturas.

Para voltar ao modo antigo, execute o Compose sem o override RSA, recriando Identidade e BFF. Preserve o segredo HMAC original e faça novo login. Nunca use `down -v` para essa troca.

## Como comprovamos

Os testes do BFF usam um servidor HTTP local de teste que fornece uma chave pública e simula a consulta de Identidade. Com assinatura válida, a consulta chega ao serviço. Com assinatura falsa, chave desconhecida, algoritmo HMAC, emissor/audiência inválidos, expiração ausente ou vencida, ela é bloqueada antes do encaminhamento. Um teste separado verifica a recusa quando JWKS está indisponível.

Esses testes não substituem o ambiente completo com Docker e PostgreSQL. Eles também não significam que Gateway, Frota, Operações e Indicadores já validem JWT.

Próximo passo de negócio: implementar a matriz de permissões e, depois, os cadastros de Frota. A Sprint 1 continua aberta.
