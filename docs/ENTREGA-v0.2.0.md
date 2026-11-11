# Evidências — v0.2.0, 20/10/2026

## Implementado

Login da interface pelo Gateway/BFF, confirmação do identificador em Identidade, sessão em memória, expiração e saída local. Não houve mudança em schema, chave JWT ou credenciais. A validação do token é delegada a Identidade; BFF e Gateway não recebem a chave.

## Verificado

- Maven Wrapper com JDK 21: build dos seis serviços aprovado.
- 63 testes de backend aprovados: Identidade 23, Frota 5, Operações 5, Indicadores 5, BFF 20, Gateway 5.
- 17 testes de frontend aprovados, incluindo casos de sucesso, senha errada, token recusado, expiração, logout, contrato inválido e rede indisponível.
- TypeScript e build Vite aprovados.
- Compose validado estruturalmente; endpoints de negócio internos continuam bloqueados no Gateway.
- Testes HTTP reais do BFF e Gateway usam um servidor simulado para o próximo serviço. Testes da interface usam jsdom.
- Versionamento local em Git, preservando histórico de v0.1.0 e acrescentando v0.2.0. Nenhum remoto configurado.

## Não comprovado / limitações

Docker continua indisponível; não foi possível comprovar o fluxo com PostgreSQL e usuário real, nem aplicar migrações nesta etapa. Não houve inspeção visual em navegador real. Não há cadastros de Frota, perfis, refresh/revogação, limitação de tentativas ou microfrontends independentes. Logout remove a sessão da página, mas não revoga tokens emitidos.

A v0.2.0 não conclui a Sprint 1 e não libera a Sprint 2 ou publicação na internet. Próximos passos: validar Docker/bancos, implementar autorização e cadastros com regras de negócio confirmadas.

## Organização da entrega

Use a pasta Downloads/NexFleet como workspace de desenvolvimento. ZIPs versionados são cópias de entrega, sem senhas locais, dependências baixadas, binários de build ou legado. O Git local é incluído. A empacotação preserva os bytes do workspace para evitar divergências artificiais de fins de linha entre o índice Git e arquivos extraídos no Windows.
