# ADR 0006 — Introdução opt-in de RSA e JWKS

Data: 20/10/2026. Estado: implementada para estudo local.

## Contexto e decisão

HS256 funciona com um segredo que tanto assina quanto verifica tokens. Distribuí-lo aos serviços daria a todos a capacidade de criar tokens. Introduzimos o perfil explícito `jwt-rsa`, com RS256 e chave RSA externa PKCS#8 de pelo menos 2048 bits. O gerador local usa 3072 bits.

A chave pública é derivada da privada; seu thumbprint define o `kid`. O endpoint interno `GET /.well-known/jwks.json` publica exclusivamente a chave pública. Não há rota nova no Gateway. BFF continua delegando `/me` a Identidade, sem guardar chave privada ou segredo HMAC.

## Compatibilidade e migração

- Sem o perfil, a configuração HS256 existente continua funcionando. Essa compatibilidade é temporária para o ambiente de estudo.
- Com o perfil, os beans HMAC não são criados e `JWT_SECRET` não é usado pelo aplicativo. A interpolação do Compose base ainda exige essa variável; preserve o arquivo de ambiente existente.
- Nenhuma tabela ou migração Flyway é alterada. Login e `/me` preservam seus contratos.
- Ativação exige chave previamente criada e montada somente em Identidade. Não existe chave padrão, geração automática em startup nem fallback silencioso se o arquivo for inválido.
- Nesta etapa não há aceitação simultânea de HS256 e RS256. Faça a troca em janela local sem uso, reinicie Identidade e realize novo login. Tokens antigos serão recusados.
- Não misture réplicas HMAC e RSA. Esta solução ainda não suporta rollout sem interrupção ou rotação com sobreposição de chaves.
- Rollback: retire o override RSA, retorne à configuração/segredo anterior e recrie Identidade. Dados permanecem; tokens RSA deixam de funcionar, exigindo novo login.

## Limites

Validação distribuída nos serviços de domínio, rotação, armazenamento de produção (Azure Key Vault), autorização por perfis e revogação continuam pendentes. O endpoint JWKS por si só não torna os serviços consumidores: cada um ainda precisará verificar assinatura, emissor, audiência e validade. A URL de emissor atual é uma identificação local, não um servidor OIDC implementado.

Referência: [Spring Security — JWT Resource Server](https://docs.spring.io/spring-security/reference/servlet/oauth2/resource-server/jwt.html).
