# Aula 21 — contratos executáveis e smoke E2E

## Objetivo

Nesta aula, você vai entender como o NexFleet detecta incompatibilidades entre documentação, rotas, eventos e componentes em execução.

## 1. Três testes diferentes

Um teste unitário verifica uma classe ou regra pequena. Um teste de contrato verifica o formato combinado entre produtor e consumidor. Um teste E2E percorre os componentes reais como um cliente faria.

No NexFleet:

```text
quality/ContractFilesTest
        ↓ estrutura dos YAMLs
contracts/*.openapi.yaml + eventos.asyncapi.yaml

Test-ApiContracts.ps1
        ↓ HTTP real
Gateway → BFF → Identidade/Frota/Operações/Indicadores → PostgreSQL

Test-E2E.ps1
        ↓ integração operacional
RabbitMQ → Indicadores/Function → DLQ/Bancos + Prometheus
```

Esses testes se complementam. Nenhum deles, sozinho, prova todo o sistema.

## 2. OpenAPI e AsyncAPI

OpenAPI descreve HTTP: caminho, verbo, parâmetros, autenticação, corpo e resposta. O projeto possui dez documentos `.openapi.yaml`.

AsyncAPI descreve comunicação assíncrona. [`eventos.asyncapi.yaml`](../../contracts/eventos.asyncapi.yaml) registra:

- as duas routing keys;
- a operação `send`;
- os nomes versionados dos eventos;
- cabeçalhos RabbitMQ;
- schemas dos payloads;
- `correlationId` obrigatório para eventos novos.

O consumidor ainda aceita eventos antigos sem esse campo, usando `eventoId` como fallback. Compatibilidade de leitura não torna o campo opcional para novos produtores.

## 3. Executar somente os contratos

Depois de ativar o JDK 21 com `Use-Local-Toolchain.ps1`, execute na raiz:

```powershell
./services/mvnw.cmd --batch-mode --no-transfer-progress `
  "-Dmaven.repo.local=$PWD/.cache/maven-repository" `
  -f ./quality/pom.xml verify
```

O resultado esperado é `Tests run: 2` e `BUILD SUCCESS`.

## 4. O que a verificação estática impede

`ContractFilesTest` falha quando:

- dois campos YAML usam a mesma chave;
- um `$ref` aponta para algo inexistente;
- uma operação não tem `operationId` ou resposta 2xx;
- um `{id}` não possui parâmetro de caminho obrigatório;
- uma rota protegida não declara segurança;
- o inventário web perde ou ganha rota sem revisão;
- o AsyncAPI perde canal, routing key ou correlação obrigatória.

## 5. Validar respostas reais

Com o Compose e o usuário local ativos:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File "./scripts/Test-ApiContracts.ps1"
```

O script:

1. verifica o ambiente;
2. entra usando as credenciais do `.env.sprint0`, sem imprimi-las;
3. confirma `/auth/me`;
4. aplica a expectativa de Administrador ou Gestor na rota de usuários;
5. consulta as listas de Frota e Operações;
6. consulta o Dashboard;
7. exige que toda resposta devolva o UUID de correlação enviado.

Ele não cadastra, edita ou inativa dados de negócio.

## 6. Executar o smoke E2E completo

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File "./scripts/Test-E2E.ps1"
```

Além das APIs, esse comando verifica consumidores e DLQs, publica duas vezes o mesmo evento de teste, confirma uma única notificação, envia uma mensagem inválida à DLQ e confirma os seis alvos no Prometheus.

Para omitir uma parte durante diagnóstico:

```powershell
./scripts/Test-E2E.ps1 -SkipServerless
./scripts/Test-E2E.ps1 -SkipObservability
```

## 7. Execução na CI

O workflow [`.github/workflows/e2e.yml`](../../.github/workflows/e2e.yml) usa um runner Linux vazio. Ele gera segredos aleatórios e uma chave RSA, define uma senha exclusiva de teste, constrói o Compose, provisiona a conta, executa o E2E e chama `down --volumes` em uma etapa `always()`.

Isso permite testar inicialização do zero sem tocar no banco local de um desenvolvedor.

## 8. Quando atualizar os contratos

Atualize o contrato junto com o código quando houver mudança de rota, verbo, campo obrigatório, status HTTP, evento, routing key, cabeçalho ou versão. A ordem recomendada é:

1. contrato;
2. produtor ou controller;
3. consumidor ou cliente;
4. testes unitários/HTTP;
5. contratos estáticos;
6. E2E.

Se a mudança quebrar consumidores existentes, crie uma nova versão em vez de alterar silenciosamente o significado da versão atual.
