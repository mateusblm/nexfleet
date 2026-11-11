# ADR 0024 — backup e recuperação isolada para CQ10

- Estado: aceita para a quinta fatia da Sprint 4.
- Data: 08/11/2026.
- Escopo: Sprint 4, v0.19.0.

## Contexto

CQ10 exige RPO de até 24 horas e RTO de até 4 horas. Apenas gerar arquivos não demonstra recuperação. Restaurar sobre os bancos locais em uso, por outro lado, seria destrutivo e desnecessário para a prova.

## Decisão

Foram separadas duas responsabilidades:

- `Backup-Databases.ps1` cria dumps customizados dos cinco PostgreSQL, manifesto de tabelas/linhas e SHA-256;
- `Test-Recovery.ps1` cria backups temporários, restaura cada banco em um contêiner PostgreSQL 18 isolado e compara as contagens.

Os restauradores não publicam portas, usam `--network none` e existem somente durante o teste. A autenticação `trust` é limitada a esses contêineres descartáveis e inacessíveis pela rede; não altera a configuração dos bancos NexFleet. Os backups temporários são removidos depois da prova. Backups preservados ficam em `backups/`, fora do Git.

O RPO observado é a idade do ponto criado. O RTO começa depois que os arquivos já existem e inclui inicialização, restauração e conferência dos cinco bancos. Um erro de checksum, `pg_restore`, tabela ausente ou contagem divergente reprova o ensaio.

## Consequências

- A recuperação passa a ser testável sem colocar dados locais em risco.
- O fluxo comprova integridade de arquivo e conteúdo básico, não apenas sucesso do comando.
- Cada banco possui uma cópia consistente própria; não existe snapshot transacional global entre microsserviços.
- Dumps preservados contêm dados potencialmente sensíveis e exigem proteção fora do escopo do repositório.
- Produção ainda precisa de agenda automática, retenção, criptografia, redundância e teste na infraestrutura Azure.

O resultado de referência está em [Evidência CQ10](../EVIDENCIA-CQ10-RECUPERACAO.md).
