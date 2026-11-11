# ADR 0005 — Login web com validação delegada

Data: 20/10/2026. Estado: adotada para estudo local.

## Decisão

Adicionar POST /api/v1/auth/login e GET /api/v1/auth/me em BFF e Gateway. A validação criptográfica permanece em Identidade, chamada pelo BFF. Nenhuma chave de assinatura é distribuída para BFF, Gateway ou navegador. Isso não substitui a evolução para assinatura assimétrica antes da validação independente pelos serviços de domínio prevista na ADR 0004.

Sessão do frontend apenas em memória, sem cookies de autenticação ou armazenamento persistente. Login limpa a senha após cada tentativa e confirma o token em /me antes de mostrar o usuário. Respostas de autenticação não devem ser armazenadas em cache.

## Consequências e limites

Identidade precisa estar disponível para confirmar a sessão. BFF usa timeouts e diferencia credenciais inválidas de falhas do serviço sem propagar detalhes internos. Logout é local, não revogação. Não há perfis, cadastros, limitação de tentativas ou autorização distribuída. Não publicar esta versão como produção.

## Compatibilidade

Os endpoints anteriores e o esquema do banco não mudam. Não há migração de dados. Rollback para v0.1.0 remove a interface e o encaminhamento novos, preservando usuários. A configuração JWT_SECRET existente permanece válida.
