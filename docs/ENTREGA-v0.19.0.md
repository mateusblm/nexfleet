# Entrega v0.19.0 — backup e recuperação CQ10

Data: 08/11/2026.

## Resultado

A quinta fatia da Sprint 4 formaliza CQ10. Os cinco bancos PostgreSQL agora possuem backup local automatizado com manifesto e checksum, além de restauração testada em contêineres isolados que nunca alteram os bancos em uso.

## Componentes entregues

- `Backup-Databases.ps1`: dumps de Identidade, Frota, Operações, Indicadores e Notificações;
- `Test-Recovery.ps1`: checksum, restauração isolada e conferência de linhas;
- `backups/` excluído do Git;
- opção `-IncludeRecovery` no E2E e execução na CI efêmera;
- ADR 0024, Aula 23 e relatório de evidência CQ10.

## Prova local

Os cinco bancos e suas 16 tabelas foram restaurados e comparados sem divergências. Na execução integrada mais recente, o RPO observado foi 0,25 minuto, contra o limite de 24 horas. O RTO conjunto foi 0,72 minuto, contra o limite de 4 horas.

## Estado da Sprint 4

CQ09 e CQ10 estão aprovados localmente. CQ06, repetição dos ensaios na homologação, revisão final de diagramas, decisão do provedor externo e publicação HTTPS na Azure continuam pendentes. Produção também exige agenda automática, retenção, criptografia e armazenamento externo dos backups.
