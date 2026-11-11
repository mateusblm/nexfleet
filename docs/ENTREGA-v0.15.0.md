# Entrega v0.15.0 — Sprint 4 com observabilidade e experiência web

## Resultado

A Sprint 4 foi iniciada sem antecipar recursos pagos da Azure. Gateway, BFF, Identidade, Frota, Operações e Indicadores agora publicam métricas Micrometer para um Prometheus local. O frontend também recebeu uma identidade visual corporativa responsiva, preservando os microfrontends e os contratos reais existentes.

## Componentes

- dependência `micrometer-registry-prometheus` nos seis serviços;
- endpoint `/actuator/prometheus` nos seis processos; BFF e serviços ficam internos, e o Gateway disponibiliza somente as próprias métricas no loopback;
- Prometheus LTS no Compose, ligado somente a `127.0.0.1:9090`;
- retenção local de sete dias e coleta a cada 15 segundos;
- `Test-Observability.ps1` valida os seis alvos;
- `Install-Dependencies.ps1` prepara runtimes e dependências locais;
- `STATUS-SPRINTS.md` separa concluído, em andamento e pendente.
- shell com login renovado, sidebar recolhível, navegação móvel, estados de feedback e acessibilidade por teclado;
- Painel, Frota, Operações e Administração de usuários com cartões, formulários, estados vazios e hierarquia visual consistentes;
- adaptação do visual recebido sem importar TanStack Start, Nitro, Supabase, SSR ou dados mockados para a aplicação principal.

## Verificação

Foram aprovados 165 testes dos serviços Java, 6 testes da Function, 43 testes frontend e quatro builds Vite. A auto-configuração do Spring confirmou o registro Prometheus nos testes de contexto. O instalador baixou novamente as quatro árvores npm e confirmou o cache Maven com Node.js 24.22.2 e JDK 21.0.13.

O Compose completo foi executado no Docker Desktop 29.9.2. Foram aprovados o caminho Gateway → BFF → quatro serviços → bancos, a topologia RabbitMQ, a Function, o login RSA e a coleta Prometheus dos seis serviços Java. A Sprint 4 permanece em andamento pelas evidências formais de qualidade, revisão de diagramas e publicação Azure ainda pendentes.

No Docker Desktop para Windows, segredos baseados em arquivo são apresentados como `0600 root:root`. O overlay `compose.jwt-rsa.yaml` passou a usar um inicializador efêmero que copia a chave para um volume temporário com proprietário `10001` e modo `0400`; o serviço Identidade permanece não-root e a chave privada não entra na imagem.
