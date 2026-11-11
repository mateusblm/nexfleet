# ADR 0001 - Stack base do MVP

- Estado: decisão histórica; versões efetivas desta entrega estão nos POMs e em frontend/package-lock.json (React 19.3.1).
- Contexto: o MVP precisa de interface web, API, persistência relacional, execução local reproduzível e caminho para Azure.
- Decisão: React 19.2 + TypeScript + Vite 8; Java 21 + Spring Boot 4.1.1; PostgreSQL 18 + Flyway; Docker Compose local; serviços gerenciados Azure no futuro.
- Consequências: as versões principais ficam fixadas. Mudanças incompatíveis exigem nova ADR e testes.

