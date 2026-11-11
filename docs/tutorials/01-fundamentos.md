# Aula 1 — Da documentação aos primeiros processos

Referência: `ArqCloud_PJBL - Completo.pdf`, enviado em 18/10/2026, especialmente as seções 16.4, 16.5 e 17.

## O objetivo desta etapa

Esta é a primeira parte da Sprint 0. A entrega é uma consulta técnica que percorre Gateway → BFF → quatro serviços → seus bancos. Ela ainda não cadastra usuários ou veículos. O objetivo é comprovar a comunicação e a separação dos dados antes de acrescentar regras de negócio.

Uma aplicação é um programa em execução. Nesta arquitetura, cada microsserviço é uma aplicação Java independente: tem seu `pom.xml`, sua classe `Application`, sua configuração, seu processo e seu banco. Um monorepositório apenas guarda esses projetos juntos; não transforma os processos em um monólito.

## O que cada parte faz

| Parte | O que é e por que existe | Quando usar no NexFleet |
|---|---|---|
| Gateway | Porta de entrada das APIs. Encaminha a requisição ao BFF. | Toda chamada pública da interface. Nesta etapa permite apenas a consulta técnica. |
| BFF | Backend da interface web. Consulta as quatro APIs e compõe uma resposta. | Quando uma tela precisa reunir informações de serviços distintos. Não faz SQL. |
| Identidade | Futuro dono de usuários, senhas e perfis. | Login e administração de contas na Sprint 1. |
| Frota | Futuro dono de veículos, motoristas e vínculos. | Cadastros e validação pública de referências. |
| Operações | Futuro dono de abastecimentos, manutenção e hodômetro. | Registros transacionais na Sprint 2. |
| Indicadores | Futuro dono das projeções do painel. | Consultas agregadas na Sprint 3. |
| PostgreSQL | Banco relacional exclusivo de cada serviço. | Persistência. Há quatro instâncias locais, sem portas públicas. |
| Flyway | Executa scripts SQL versionados em ordem. | Evoluir cada banco sem alterações manuais esquecidas. |

## Leia o código nesta ordem

1. `services/frota/pom.xml`: Maven resolve dependências, compila, testa e empacota. O alvo é Java 21 e o Spring Boot permanece em 4.1.1, conforme a ADR existente.
2. `services/frota/src/main/java/br/com/nexfleet/frota/Application.java`: inicia o Spring Boot.
3. `consultarservico/api/ServicoController.java`: recebe HTTP e escolhe 200 ou 503. Não consulta o banco diretamente.
4. `consultarservico/application/ConsultarServico.java`: coordena a consulta usando a interface `VerificarBanco`. Não importa Spring.
5. `consultarservico/infrastructure/JdbcVerificarBanco.java`: implementa a interface usando JDBC e `SELECT 1`.
6. `config/UseCaseConfig.java`: conecta a aplicação ao adaptador. Essa composição fica fora da aplicação.
7. `src/test/.../ArchitectureTest.java`: ArchUnit verifica as dependências compiladas e reprova importações proibidas.

Essa pasta por funcionalidade é a primeira fatia vertical. As dependências apontam de `api` para `application`; `infrastructure` implementa uma porta da aplicação. Ainda não há entidades de negócio: elas serão introduzidas nas fatias de cadastro, com testes específicos para o pacote `domain`.

## Como executar localmente

Pré-requisito: Docker Desktop instalado e com o motor Linux funcionando. `docker version` precisa mostrar Client e Server. Os contêineres trazem Java 21 e Maven; não exigem instalar essas ferramentas no Windows para executar o ambiente.

Na raiz do projeto, execute no PowerShell:

```powershell
Copy-Item .env.sprint0.example .env.sprint0
# Edite as quatro senhas e gere JWT_SECRET no arquivo .env.sprint0 (veja Aula 3).
docker compose --env-file .env.sprint0 -f compose.sprint0.yaml config --quiet
docker compose --env-file .env.sprint0 -f compose.sprint0.yaml up --build -d --wait
./scripts/Test-Sprint0.ps1
```

O primeiro comando de cópia é necessário apenas uma vez; não sobrescreva seu arquivo de senhas em execuções futuras. A primeira construção baixa imagens e dependências e pode demorar. Se a porta 8080 estiver ocupada, altere `GATEWAY_PORT` e passe a mesma porta ao teste.

Abra `http://localhost:8080/api/v1/ambiente`. O resultado esperado é:

```json
{
  "application": "NexFleet",
  "stage": "sprint-0",
  "status": "UP",
  "services": [
    { "name": "identidade", "status": "UP" },
    { "name": "frota", "status": "UP" },
    { "name": "operacoes", "status": "UP" },
    { "name": "indicadores", "status": "UP" }
  ]
}
```

`200` significa que os quatro serviços responderam e seus bancos estavam acessíveis. `503` com `DEGRADED` significa que ao menos um serviço ou banco não respondeu. Isso é uma fotografia do ambiente, não uma garantia sobre requisições futuras. O BFF usa limites de conexão e leitura para não aguardar indefinidamente.

Para acompanhar e parar:

```powershell
docker compose --env-file .env.sprint0 -f compose.sprint0.yaml ps
docker compose --env-file .env.sprint0 -f compose.sprint0.yaml logs --tail=100 frota
docker compose --env-file .env.sprint0 -f compose.sprint0.yaml down
```

O comando `down` acima mantém os volumes. Não use `down -v` para encerrar um dia de estudo: isso remove os volumes e os dados.

## Como os bancos ficam separados

Cada PostgreSQL está numa rede própria. Apenas o respectivo serviço participa dessa rede. Cada instância tem banco, usuário, senha, volume e histórico Flyway próprios. O BFF e o Gateway não têm conexão de banco. O PostgreSQL 18 usa o volume em `/var/lib/postgresql`; os volumes antigos do Compose anterior não são reutilizados.

Na primeira migração, identificamos o schema de cada serviço. As tabelas reais serão adicionadas por novas migrações nas sprints das funcionalidades. Uma migração aplicada não deve ser editada: criamos a próxima versão.

As credenciais de proprietário do PostgreSQL são uma simplificação local. Antes de produção, separar o usuário de migrações do usuário da aplicação e restringir privilégios.

## Como testar sem subir os bancos

Com JDK 21 e Maven instalados:

```powershell
mvn -f services/pom.xml verify
```

Para testar um serviço de forma independente:

```powershell
mvn -f services/frota/pom.xml verify
```

Os testes unitários simulam a porta do banco; não provam Flyway/PostgreSQL. O teste HTTP do Gateway sobe um BFF de teste local. A comprovação completa de banco e migração depende de executar os contêineres e o teste de ambiente.

O workflow `.github/workflows/backend.yml` prepara Java 21, roda os testes e valida o Compose quando este diretório for publicado como repositório GitHub. Criar o arquivo do workflow não significa que ele já executou no GitHub.

## Limites desta primeira parte da Sprint 0

- As consultas técnicas são públicas apenas no ambiente local, exposto em `127.0.0.1`. As outras rotas são negadas. JWT, BCrypt e regras por perfil vêm com Identidade; não há dados pessoais nessa consulta.
- HTTP local serve ao estudo. HTTPS e políticas completas do Gateway precisam ser implementados antes de homologação/publicação.
- O frontend React, shell e microfrontends ainda não foram implementados nesta etapa.
- RabbitMQ, outbox, idempotência e a função serverless serão implementados nas sprints 2 e 3, conforme o PDF.
- `backend/` e `compose.yaml` antigos ficaram na pasta original, fora desta entrega organizada. A execução usa `services/` e `compose.sprint0.yaml`.

## Exercício para entender a arquitetura

Com o ambiente funcionando, pare somente Frota: `docker compose --env-file .env.sprint0 -f compose.sprint0.yaml stop frota`. Consulte novamente `/api/v1/ambiente`: deve receber 503 e Frota deve aparecer como `DOWN`. Reinicie com `docker compose --env-file .env.sprint0 -f compose.sprint0.yaml start frota` e aguarde a recuperação. Isso demonstra por que sistemas distribuídos precisam tratar falhas parciais.

A próxima etapa fecha a Sprint 0 com shell e microfrontends, antes de avançar para autenticação e cadastros.
