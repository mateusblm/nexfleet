# ADR 0004 — Primeiro incremento de autenticação

Data: 19/10/2026. Estado: adotada para estudo local; não aprovada para publicação.

## Decisão

- Implementar login na fatia `identidade/autenticar`, com portas de busca, senha e emissão de token.
- Armazenar somente hashes BCrypt custo 12. Rejeitar senhas acima de 72 bytes para não aceitar truncamento silencioso.
- Emitir tokens de 15 minutos sem dados pessoais, com emissor, audiência e ID de usuário.
- Usar HS256 apenas no serviço Identidade neste incremento. Segredo aleatório externo de pelo menos 32 bytes. Nenhuma chave padrão ou exposição da chave ao frontend.
- Antes de validação distribuída, migrar a assinatura para chave assimétrica/JWKS; não compartilhar a capacidade de assinatura com BFF/Frota.
- Provisionamento opcional `local-seed` explicitamente ativado, sem senha padrão, sem atualização de contas existentes, nunca em nuvem.

## Migração e compatibilidade

V2 acrescenta `identidade.usuario`, sem alterar V1 ou outros bancos. A aplicação anterior não lê a nova tabela; rollback do aplicativo preserva a tabela e os usuários. Não executar DROP ou Flyway clean. O novo aplicativo requer JWT_SECRET; atualizar a configuração antes de iniciar. O restante do contrato técnico de disponibilidade permanece igual.

## Limitações e próximos passos

Não há login pelo Gateway/BFF/interface, matriz de perfis, refresh, revogação, limitação de tentativas ou recuperação de senha. Desativar uma conta impede novos logins, mas não invalida tokens existentes imediatamente. Esses pontos impedem tratar o incremento como pronto para produção. A integração com PostgreSQL real ainda exige Docker disponível.
