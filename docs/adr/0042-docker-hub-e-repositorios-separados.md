# ADR 0042 — Docker Hub e nove repositórios públicos separados

Data: 11/11/2026
Estado: aceita

## Contexto

Os requisitos da v1.0.0 pedem que cada componente esteja em um **repositório público próprio**, com README, e que as imagens estejam no **Docker Hub**. Até a v0.30.0, todo o código vivia em um monorepo e as imagens iam para um Azure Container Registry (ACR) privado, puxado pelos Container Apps com identidade gerenciada e o papel `AcrPull` (ADRs 0034 e 0037). O ACR também era um custo fixo.

## Decisão

1. **Nove repositórios públicos em `github.com/mateusblm`:**

   | Repositório | Conteúdo |
   |---|---|
   | `nexfleet` (guarda-chuva) | `docs/`, ADRs, `contracts/`, `infra/` (Bicep, bootstrap SQL, RabbitMQ), Compose, `quality/` e scripts |
   | `nexfleet-frontend` | shell React e os microfrontends Frota, Operações e Painel |
   | `nexfleet-gateway` | API Gateway (Spring Cloud Gateway) e Swagger UI única |
   | `nexfleet-bff` | BFF web |
   | `nexfleet-identidade` | login, JWT RSA e usuários |
   | `nexfleet-frota` | veículos, motoristas e vínculos (MongoDB) |
   | `nexfleet-operacoes` | abastecimentos, manutenções e outbox |
   | `nexfleet-indicadores` | projeções e dashboard |
   | `nexfleet-function` | Azure Function de notificação e de eficiência |

2. **Histórico preservado:** cada repositório de serviço foi criado com `git subtree split` da pasta original do monorepo, mantendo os commits e a autoria de toda a equipe.
3. **Build independente:** cada serviço Java tem Maven Wrapper, Dockerfile próprio e passa em `./mvnw -B -ntp verify` clonado sozinho; o frontend passa em `npm ci && npm test && npm run build` em cada pasta.
4. **CI (GitHub Actions) por repositório:** os testes rodam em todo push e pull request. Em tag `v*`, e só se os testes passarem, o job `publicar` gera a imagem e a envia ao Docker Hub com as tags `<tag>` e `latest`, usando os secrets `DOCKERHUB_USERNAME` e `DOCKERHUB_TOKEN`. Imagens: `mateusblm/nexfleet-{gateway,bff,identidade,frota,operacoes,indicadores,function}`. A imagem da Function serve só à execução local; na Azure ela é publicada como pacote. O frontend não tem imagem: vai para o Static Web Apps.
5. **CI do guarda-chuva:** clona os repositórios irmãos (na mesma branch, se existir) e roda o `quality/` com `-Dnexfleet.repos.dir`, para conferir diagramas e tabelas contra o código.
6. **Azure sem registry:** os Container Apps puxam `docker.io/mateusblm/nexfleet-<svc>:<tag>` (`containerImagePrefix` + `containerImageTag`, padrão `v1.0.0`), sem bloco `registries` e sem credencial. O ACR e as atribuições `AcrPull` saíram do Bicep.
7. **Execução local a partir do guarda-chuva:** `compose.yaml` sobe tudo com as imagens do Docker Hub; `compose.build.yaml` compila a partir de `../nexfleet-*`, que `scripts/clonar-tudo.sh` clona lado a lado.

## Consequências

- O avaliador encontra cada componente em um repositório próprio e baixa as imagens sem credencial.
- As imagens são públicas: nenhum segredo pode entrar nelas; a configuração sensível chega só por variável de ambiente ou secret.
- Uma mudança que atravessa serviços vira vários commits em vários repositórios; não há commit atômico entre eles. O `quality/` do guarda-chuva é quem confere a coerência dos contratos e diagramas.
- O CI só publica quando os secrets `DOCKERHUB_*` estão gravados no repositório; sem eles, o job `publicar` falha e nenhuma imagem é enviada.
- O monorepo original não foi alterado e continua sendo a referência da v0.30.0.

## Alternativas rejeitadas

- **Manter o ACR:** custo fixo e imagens privadas, contra os requisitos.
- **GitHub Container Registry:** os requisitos pedem o Docker Hub.
- **Copiar as pastas sem histórico:** apagaria a autoria dos commits da equipe.
