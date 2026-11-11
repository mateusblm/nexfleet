# ADR 0008 — Gestão de usuários conforme RF02/RF03

Data: 20/10/2026. Estado: implementada, validação com PostgreSQL real pendente.

## Decisão

Identidade possui cadastro, consulta paginada, edição de e-mail/perfil/estado e desativação lógica de usuários. Somente Administrador ativo pode executar essas operações. Gestor recebe 403 mesmo chamando a API diretamente. A interface acessa Gateway e BFF; o BFF não consulta banco nem decide a regra de negócio.

JWT contém `perfil` tipado como ADMINISTRADOR ou GESTOR_FROTA. Spring Security verifica o token e exige a autoridade administrativa. O caso de uso também verifica o estado atual do administrador no banco em cada chamada. Isso impede que um token administrativo antigo autorize chamadas subsequentes depois da desativação/rebaixamento confirmados. Não é revogação global de JWT nem cancelamento de uma requisição que já estava em execução.

E-mails são normalizados; o índice único existente é a proteção concorrente contra duplicidade. Senha inicial segue a política local já existente: pelo menos 12 caracteres, até 72 bytes UTF-8, hash BCrypt custo 12. Respostas usam DTO sem senha/hash e cache desabilitado. Editar não troca a senha; recuperação/troca de senha não integra esta etapa.

## Migração e compatibilidade

V3 adiciona `perfil` com restrição dos dois valores e padrão GESTOR_FROTA. Nenhuma conta existente ganha administração, nenhum registro ou hash é apagado. V1/V2 permanecem imutáveis. O padrão também mantém inserts de aplicativos antigos compatíveis com o schema expandido.

Sequência local: backup; migrar Identidade por Flyway; atualizar Identidade/BFF/Gateway/interface; fazer novo login. `/me` acrescenta perfil sem remover o ID. Clientes anteriores ignoram o campo novo; clientes novos aceitam ausência durante a transição, sem oferecer ações administrativas. Tokens antigos sem perfil não autorizam gestão de usuários.

Rollback: voltar os aplicativos, mantendo V3 e os dados. Não executar DROP, clean ou remover volumes. Durante implantação mista, só a versão nova suporta gestão; por isso a atualização local deve ocorrer em janela sem uso. Não há garantia de rollout sem interrupção.

O seed local aceita `LOCAL_USER_PROFILE`, padrão GESTOR_FROTA. ADMINISTRADOR precisa ser informado explicitamente para criar uma conta nova. `ON CONFLICT DO NOTHING` preserva senha, estado e perfil de conta já existente. Não há promoção automática de conta antiga nem seed de produção.

## Limites

Regra de impedir remoção do último administrador não está definida no PJBL e não foi inventada. O operador deve manter uma conta administrativa de recuperação; não rebaixar/desativar a última conta. Provisionamento de produção e política de recuperação precisam de decisão antes da Azure.

Ainda faltam integração real com PostgreSQL, testes de migração/índices, auditoria operacional completa e aplicação de permissões nos serviços de Frota/Operações futuros. RF03 não está concluído em todo o sistema. A tela administrativa fica no shell; os MFEs de domínio permanecem pendentes.
