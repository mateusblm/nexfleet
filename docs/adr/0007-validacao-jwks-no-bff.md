# ADR 0007 — BFF verifica tokens pela chave pública

Data: 20/10/2026. Estado: implementada para estudo local.

## Decisão

No perfil `jwt-rsa`, o BFF usa o suporte Resource Server do Spring Security para verificar RS256 pelo JWKS de Identidade, antes de permitir `GET /api/v1/auth/me`. Exige emissor `https://nexfleet.local/identidade`, audiência `nexfleet-api` e expiração. HS256 não é aceito neste modo.

O BFF não recebe chave privada, segredo HMAC ou acesso ao banco de Identidade. Chaves públicas são obtidas do endereço de Identidade configurado pelo operador, nunca de uma URL enviada no token. Há limites de conexão de 2 segundos e leitura de 3 segundos por chamada JWKS. O cache é gerenciado pela biblioteca; isso não implementa revogação imediata.

A consulta `/me` continua sendo encaminhada a Identidade após a verificação local. Preservamos o contrato existente; a redundância é intencional nesta etapa. Ela não consulta status da conta no banco nem revoga tokens. Identidade indisponível ainda impede concluir a consulta de sessão.

## Migração e reversão

- Sem `jwt-rsa`, permanece a validação delegada anterior.
- O override `compose.jwt-rsa.yaml` agora ativa o perfil em Identidade e BFF. Use rebuild/recriação dos dois serviços, em janela local sem usuários ativos.
- Não alteramos bancos, formato do login nem armazenamento do token na interface.
- Não misture BFF RSA com Identidade HMAC. Ativação exige configuração RSA da Aula 5 e novo login.
- Para rollback, retire o override nos dois serviços, preserve o segredo legado e faça novo login. Não remova volumes.
- No perfil RSA não há fallback para o modo delegado quando a chave não pode ser obtida. Sem verificação válida, o acesso é recusado.

## Limites

Esta é a primeira verificação em outro processo, não a conclusão da segurança distribuída. Gateway e serviços de domínio ainda precisam de proteção própria nos futuros endpoints. Autenticação não concede permissão de administrador ou gestor: a matriz da ADR 0002 ainda precisa ser implementada. Não foram criados papéis fictícios.

HTTP interno é exclusivo da rede local de estudo. Publicação requer revisão de TLS, endereço de emissor, distribuição/rotação de chaves e infraestrutura. O modo legado será removido somente em uma migração posterior planejada.

Referência: [Spring Security — JWT Resource Server](https://docs.spring.io/spring-security/reference/servlet/oauth2/resource-server/jwt.html).
