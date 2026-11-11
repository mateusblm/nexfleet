# ADR 0001 - Stack base do MVP

- Estado: decisão histórica. Quanto ao banco, **Substituída por ADR 0039 e ADR 0040** (na v1.0.0, Frota usa MongoDB e os demais serviços usam Azure SQL/SQL Server com Flyway em T-SQL); o restante da stack continua valendo; versões efetivas desta entrega estão nos POMs e em frontend/package-lock.json (React 19.3.1).
- Contexto: o MVP precisa de interface web, API, persistência relacional, execução local reproduzível e caminho para Azure.
- Decisão: React 19.2 + TypeScript + Vite 8; Java 21 + Spring Boot 4.1.1; PostgreSQL 18 + Flyway; Docker Compose local; serviços gerenciados Azure no futuro.
- Consequências: as versões principais ficam fixadas. Mudanças incompatíveis exigem nova ADR e testes.

