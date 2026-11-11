# Sprint 1 — evidências acumuladas

## Verificação atual — 28/10/2026

- O build Docker executou 135 testes nos seis serviços com Java 21 (Identidade 42, Frota 28, Operações 5, Indicadores 5, BFF 46 e Gateway 9).
- Os dez contêineres ficaram saudáveis: Gateway, BFF, quatro serviços e quatro bancos PostgreSQL.
- Identidade aplicou Flyway V1, V2 e V3; a conta local foi gravada com perfil `ADMINISTRADOR` e hash BCrypt.
- Frota aplicou Flyway V1–V4. O banco confirmou placa única, CPF/CNH únicos e o índice parcial de um vínculo ativo por veículo.
- Fluxo público comprovado: login 200; criar veículo 201; repetir placa 409; listar por `DISPONIVEL`; atualizar 200; inativar 204; consultar estado final `INATIVO`.
- Fluxo público de motorista comprovado: criar 201; repetir CPF/CNH 409; atualizar 200; filtrar por `INATIVO`; estado final confirmado no banco.
- Fluxo público de vínculo comprovado: login, criação de veículo/motorista, vínculo 201, repetição 409, encerramento e histórico preservado. Os registros exclusivos da validação foram removidos ao final.
- BFF e Frota validaram o JWT RSA pelo JWKS de Identidade. A chave privada foi montada somente em Identidade.
- Foi corrigido o destino do segredo Compose: `identidade-jwt.pem`. Antes da correção, Identidade falhava de forma fechada, sem voltar a HMAC.
- Shell e três microfrontends passaram em 42 testes e quatro builds independentes. A base funcional da Sprint 1 está concluída localmente.
- O perfil RSA padrão do exemplo foi corrigido para não ativar o seed sem credenciais; ambos os modos do Compose foram validados.
- Nenhum recurso Azure foi criado. Sprint 2, EDA, serverless e indicadores ainda não foram iniciados.

## Verificação histórica — 19/10/2026

Data: 19/10/2026. Escopo: autenticação interna do serviço Identidade.

## Comprovado

- Build Maven completo dos seis serviços com Java 21: BUILD SUCCESS.
- 49 testes aprovados, sem falhas ou testes ignorados: Identidade 23, Frota 5, Operações 5, Indicadores 5, BFF 8, Gateway 3.
- Identidade cobre regra de login, BCrypt real, emissão/validação de JWT, expiração, assinatura/emissor/audiência incorretos, filtro HTTP, respostas 200/400/401/403, seed local e limites arquiteturais.
- O teste do seed comprova uso de hash e SQL que não sobrescreve contas; não comprova execução desse SQL no PostgreSQL.
- Compose principal e override de seed local passaram em `docker compose config --quiet` usando valores sintéticos de configuração. Nenhum recurso externo foi criado.

## Não comprovado / pendente

- Docker continua sem conexão com `dockerDesktopLinuxEngine`. Não foi possível subir os bancos, aplicar V2 ou validar unicidade/preservação de dados com PostgreSQL real.
- O login ainda não está roteado pelo Gateway/BFF nem integrado à interface. Testes HTTP de Identidade usam Spring Security real e repositório de usuários simulado.
- Não há autorização por perfis, refresh, revogação imediata, limitação de tentativas nem administração de usuários. Não publicar este incremento.
- HS256 é local a Identidade; antes da verificação distribuída, evoluir para assinatura assimétrica conforme ADR 0004.
- Testes de banco, microfrontends e integração ponta a ponta da Sprint 0 permanecem pendentes. Sprint 1 iniciada, não concluída.

## Configuração que mudou

`JWT_SECRET` passa a ser obrigatório. O exemplo é um marcador inválido intencionalmente; siga a Aula 3 para gerar a chave no arquivo local ignorado pelo Git. Não substituir senhas de banco existentes e não remover volumes. V2 é uma migração aditiva; rollback do aplicativo deve preservar a nova tabela.
