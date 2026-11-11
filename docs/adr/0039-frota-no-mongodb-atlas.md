# ADR 0039 — Frota no MongoDB Atlas

Data: 11/11/2026
Estado: aceita

## Contexto

Os requisitos da v1.0.0 pedem um microsserviço com **MongoDB Atlas**. Até a v0.30.0, a Frota guardava veículos, motoristas e vínculos em PostgreSQL, com Flyway, chaves estrangeiras e um índice parcial para o vínculo ativo (ADRs 0009–0011). A Frota é o serviço cujos cadastros são documentos independentes e sem transação com outro agregado, o que a torna a candidata natural.

O contrato HTTP da Frota (rotas, payloads e status) precisava continuar igual ao da v0.30.0, porque o BFF, Operações e os microfrontends dependem dele.

## Decisão

1. **Persistência:** a Frota usa Spring Data MongoDB (`MongoTemplate`). Os adaptadores `MongoVeiculos`, `MongoMotoristas`, `MongoVinculos` e `MongoVerificarBanco` ficam em `infrastructure/` e implementam as mesmas portas de `application/`. Domínio, casos de uso e controladores não mudaram. A Frota não tem mais JDBC, Flyway nem PostgreSQL.
2. **Coleções:** `veiculos`, `motoristas` e `vinculos`. O `_id` é o UUID do agregado gravado como texto; as referências entre coleções (`veiculoId`, `motoristaId`) também são UUIDs em texto.
3. **Índices** (`IndicesMongo`, criados na inicialização e conferidos antes de cada escrita):

   | Coleção | Índice | Regra |
   |---|---|---|
   | `veiculos` | `ux_veiculo_placa` (único) | placa única → 409 |
   | `veiculos` | `ix_veiculo_status_placa` | listagem por status |
   | `motoristas` | `ux_motorista_cpf`, `ux_motorista_cnh` (únicos) | CPF e CNH únicos → 409 |
   | `motoristas` | `ix_motorista_status_nome` | listagem por status |
   | `vinculos` | `ux_vinculo_veiculo_ativo` (único, parcial `{ativo: true}`) | no máximo um vínculo ativo por veículo (RB06), mesmo sob corrida |
   | `vinculos` | `ix_vinculo_historico_veiculo`, `ix_vinculo_historico_motorista` | histórico por veículo e por motorista |

   Se o MongoDB estiver fora na subida, o serviço sobe com readiness `DOWN` e os índices são criados na próxima escrita; nenhuma escrita acontece sem as restrições de unicidade.
4. **Readiness:** o grupo de readiness inclui `mongo`; com o banco indisponível, a Frota responde `DOWN/503`.
5. **Filtros tipados:** as consultas são montadas com `Criteria` a partir de campos do domínio, nunca com JSON vindo do usuário.
6. **Ambientes:**
   - local: `mongo:7.0` no Compose (imagem configurável por `MONGO_IMAGE`; `mongo:8` não sobe no kernel da máquina de desenvolvimento);
   - testes: Testcontainers com a mesma imagem;
   - nuvem: MongoDB Atlas M0, criado à mão (fora do Bicep), com usuário `frota`. A connection string chega pelo parâmetro seguro `mongodbUri` e vira o secret `MONGODB_URI` do Container App. Recomenda-se `serverSelectionTimeoutMS=3000` na URI, para o probe de readiness não esperar 30 s quando o Atlas está fora.

## Consequências

- O contrato HTTP da Frota foi preservado; BFF, Operações e frontend não mudaram.
- **Sem chave estrangeira:** a "proteção final" da ADR 0038 (FK de `veiculo_motorista`) deixa de existir. A exclusão definitiva de veículo verifica `vinculos` e depois remove com filtro `status = INATIVO`; as duas operações não são atômicas entre coleções. Um vínculo criado no intervalo depende de a criação de vínculo recusar veículo inativo, regra do caso de uso de vínculos.
- Não houve migração de dados: a v1.0.0 começou com coleções vazias.
- A lista de IPs do Atlas M0 fica aberta, porque os Container Apps não têm IP de saída fixo. O risco foi aceito pelo responsável (spec da v1.0.0): TLS obrigatório e senha forte gerada.
- A prova de recuperação do CQ10 (ADR 0024) foi feita com PostgreSQL na v0.30.0 e não foi repetida para a Frota no MongoDB.

## Alternativas rejeitadas

- **Spring Data repositories com `@Document`:** acoplariam o domínio às anotações do MongoDB ou exigiriam um segundo modelo; o `MongoTemplate` no adaptador mantém o domínio limpo.
- **Colocar outro serviço no MongoDB:** Operações depende de transação entre abastecimento, hodômetro e outbox (ADR 0013); Identidade e Indicadores não ganhariam nada com documentos.
- **Cosmos DB com API MongoDB:** os requisitos pedem MongoDB Atlas e o M0 é gratuito.
