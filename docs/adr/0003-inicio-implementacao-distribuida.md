# ADR 0003 — Início da implementação distribuída

- Data: 18/10/2026.
- Estado: aceita para a primeira parte da Sprint 0.
- Contexto: o PDF `ArqCloud_PJBL - Completo.pdf` substitui o monólito por quatro serviços, Gateway e BFF. O diretório `backend/` ainda contém o esqueleto anterior.
- Decisão: novos projetos independentes em `services/`, agregador Maven apenas para conveniência de build e Compose próprio. Preservar o esqueleto anterior. Começar pela consulta técnica `GET /api/v1/ambiente`, com estado real dos bancos, antes dos casos de negócio.
- Versões: manter Java 21, Spring Boot 4.1.1 e PostgreSQL 18 da ADR 0001. Spring Cloud 2025.1.2 é compatível com Boot 4.1.x; usar ArchUnit 1.4.1 para as regras iniciais.
- Dados: quatro instâncias PostgreSQL locais simplificam a separação de redes e credenciais. Não reutilizar volumes do ambiente anterior. A topologia futura Azure continua com bases isoladas.
- Consequências: seis processos Java e quatro bancos consomem mais memória que um monólito. O BFF agrega respostas sem SQL; indisponibilidade produz 503. Sem migração de dados porque o esqueleto anterior não implementa cadastros.
- Segurança: somente o Gateway publica porta local; consultas técnicas GET são permitidas, demais requisições negadas. JWT, TLS, limites e correlação permanecem pendentes e não são declarados prontos.
- Alternativa: converter o antigo backend diretamente; rejeitada por dificultar comparação e recuperação durante a aprendizagem.
- Fontes técnicas: https://spring.io/projects/spring-cloud/ e https://docs.docker.com/guides/postgresql/immediate-setup-and-data-persistence/.

Esta ADR é um registro de implementação local. Sua numeração não substitui as ADRs conceituais numeradas no PDF.
