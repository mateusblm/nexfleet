# Aula 8 — Primeira fatia vertical de Frota: veículos

## O que foi construído

Uma fatia vertical é uma funcionalidade completa de cima a baixo. Aqui, “veículos” atravessa a tela React, o Gateway, o BFF, o serviço Frota, a regra de negócio e a tabela PostgreSQL. Isso é diferente de criar primeiro “todas as telas” e deixar o banco para depois: já temos algo pequeno que pode ser demonstrado e testado.

O fluxo é:

```text
Tela → /api/v1/veiculos → Gateway → BFF → /api/v1/frota/veiculos → Frota → PostgreSQL Frota
```

## Por que cada camada existe

- **Tela:** coleta os campos de RF04 e mostra filtro/status de RF15.
- **Gateway:** é a entrada pública única e aceita apenas rotas declaradas.
- **BFF:** adapta mensagens para a interface e não devolve detalhes internos de falha.
- **Caso de uso:** valida campos, perfil, paginação e normaliza a placa.
- **Porta `Veiculos`:** permite testar a regra sem Spring ou banco.
- **Adaptador JDBC:** contém o SQL e traduz duplicidade de placa em conflito 409.
- **Flyway V2:** cria a mesma estrutura em todos os ambientes de forma repetível.

Clean Architecture aparece na direção das dependências: o caso de uso conhece a interface `Veiculos`, mas não conhece `JdbcTemplate`. Vertical Slice aparece no agrupamento `gerenciarveiculos`, que contém API, aplicação e infraestrutura da mesma capacidade.

## Como executar

Veículos exigem RSA/JWKS porque o serviço Frota valida o token diretamente. Gere a chave uma vez conforme a Aula 5. Para criar a conta local e ativar os dois perfis Compose juntos, use:

```powershell
docker compose --env-file .env.sprint0 `
  -f compose.sprint0.yaml `
  -f compose.sprint1-local.yaml `
  -f compose.jwt-rsa.yaml up --build -d --wait
```

Defina `IDENTIDADE_PROFILES=local-seed,jwt-rsa` no arquivo local ou no terminal; nunca coloque senha ou chave privada no Git. Entre na interface, abra **Gerenciar veículos** e cadastre os campos solicitados.

## Regras já cobertas

- placa única no banco e resposta 409;
- placa gravada em maiúsculas;
- quilometragem inicial não negativa;
- status limitado a Disponível, Em uso, Em manutenção ou Inativo;
- paginação limitada e filtro por status;
- inativação preserva a linha e seus futuros históricos;
- somente Administrador ou Gestor de Frota autenticado acessa a API.

## O que ainda não está pronto

Motoristas e vínculos pertencem às próximas fatias da Sprint 1. RB05 será comprovada nesses comandos e depois em Operações. Em 23/10/2026, a migração V2 e o fluxo completo de veículos foram comprovados em PostgreSQL local; essa verificação complementa, mas não substitui, os testes automatizados.

## Quando usar esse padrão

Use uma fatia vertical quando quiser entregar uma capacidade observável com todas as camadas necessárias. No NexFleet, motorista, vínculo, abastecimento e manutenção devem seguir a mesma forma. Evite criar uma abstração genérica de “CRUD” para tudo: as regras de placa, CNH, hodômetro e manutenção são diferentes.
