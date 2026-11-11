# ADR 0002 - Matriz de permissões

- Estado: aceita
- Contexto: administração de identidades e operação da frota têm responsabilidades diferentes.
- Decisão: o Administrador gerencia usuários; Administrador e Gestor de Frota executam operações da frota.
- Consequências: a API diferencia permissões no backend; controles visuais do frontend são apenas auxiliares.

