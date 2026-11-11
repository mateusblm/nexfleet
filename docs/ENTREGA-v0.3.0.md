# Entrega v0.3.0 — RSA e JWKS opcionais

Data: 20/10/2026. Sprint 1 em andamento, não concluída.

## Resultado

Identidade pode emitir e validar tokens RS256 com chave privada externa e disponibilizar sua chave pública em JWKS. O perfil é opt-in. O modo HS256, o contrato do login e os dados existentes são preservados. Não foram alterados frontend, permissões de negócio, bancos nem serviços consumidores.

Esta é a etapa de disponibilização da nova configuração, não a conclusão de uma migração distribuída. A ativação e o rollback são manuais e exigem novo login; não existe compatibilidade simultânea entre tokens HMAC e RSA.

## Verificações executadas

- Build Maven completo com JDK 21: seis aplicações compiladas, 70 testes aprovados, zero falhas/erros.
- Identidade: 30 testes, incluindo 7 novos testes de RSA/JWKS e HTTP.
- Frontend inalterado: 17 testes aprovados e build TypeScript/Vite concluído.
- Geração temporária de chave RSA 3072 bits: importação validada e tentativa de sobrescrita recusada, com conteúdo preservado. O arquivo de teste foi removido; não foi criada chave de uso real.
- Validação estrutural de Compose base + override RSA: aprovada.
- `git diff --check`: sem erros de whitespace.

Os testes HTTP de Identidade usam Spring MVC/Security e repositório de usuários em memória. Eles não exercitam PostgreSQL. A verificação criptográfica usa chaves descartáveis geradas nos testes.

## Limitações observadas

O Docker Engine não estava disponível (`dockerDesktopLinuxEngine` ausente). Não foi possível iniciar contêineres, aplicar migrações ou testar login real com PostgreSQL. Validar a configuração Compose não comprova montagem da chave e permissões dentro do contêiner.

A validação independente por JWKS nos consumidores, rotação de chaves, permissões, cadastros, microfrontends e publicação Azure continuam pendentes. O endpoint é interno e não está roteado no Gateway. Não foi configurada uma chave real nem ativado RSA automaticamente no ambiente do usuário.

## Acompanhamento

Abra `NexFleet.code-workspace` e siga `docs/tutorials/05-chaves-rsa.md`. A decisão e o procedimento de reversão estão na ADR 0006. As orientações de implementação enxuta e migração segura limitaram esta entrega ao novo modo de assinatura, preservando o funcionamento anterior.
