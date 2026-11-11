# Gate para avançar à Sprint 2

**Estado desta versão: base técnica aprovada para planejar a Sprint 2.** As regras de abastecimento abaixo ainda precisam de decisão antes do primeiro caso de uso operacional.

## Já existe

- Seis aplicações Java separadas, com build agregado e testes de arquitetura.
- Bancos separados descritos no Compose; consulta técnica de disponibilidade.
- Shell React e três microfrontends Vite com builds independentes.
- Login interno de Identidade, BCrypt, JWT local, migração de usuários e seed opcional.

## Falta concluir antes das operações de negócio

- [x] Subir Docker/PostgreSQL e comprovar as migrações atuais e o isolamento de rede/bancos.
- [x] Implementar login via Gateway → BFF → Identidade → interface (v0.2.0).
- [x] Validar esse fluxo com PostgreSQL real e uma conta provisionada.
- [x] Disponibilizar assinatura RSA e JWKS como modo local opcional (v0.3.0).
- [ ] Estender a validação distribuída, já ativa em BFF/Frota, aos futuros consumidores.
- [x] Implementar usuários/perfis na administração, com testes de 401/403 e estado atual do Administrador.
- [x] Validar migração V3 e conta administrativa com PostgreSQL real.
- [x] Implementar veículos com placa única, filtro, inativação e autorização distribuída (v0.4.0).
- [x] Validar migração V2 de Frota e fluxo de veículos com PostgreSQL real.
- [x] Implementar motoristas com CPF/CNH únicos, edição, consulta e autorização (v0.5.0).
- [x] Validar migração V3 de Frota e fluxo de motoristas com PostgreSQL real.
- [x] Implementar vínculos históricos e registrar simultaneidade/CNH na ADR 0011 (v0.6.0).
- [x] Revalidar migração V4 e fluxo de vínculos em PostgreSQL real (28/10/2026).
- [x] Integrar microfrontends independentes ao shell (v0.7.0).
- [x] Definir as regras da primeira fatia de abastecimentos na ADR 0013.
- [x] Testar login → veículo → motorista → vínculo → encerramento pela API pública.

Na Sprint 2 virão abastecimentos, hodômetro, manutenção, outbox e broker. Não devem depender de cadastros fictícios ou de autorização ainda inexistente. As pendências da Sprint 0 continuam visíveis no planejamento.

## Limites desta organização

A v0.1.0 organizou a implementação sem alterações funcionais. A v0.2.0 acrescenta login pela interface e delegação por Gateway/BFF, sem alteração de schema ou compartilhamento de chave JWT. Os registros em VERIFICACAO-SPRINT0/1 e VERIFICACAO-FRONTEND são históricos. Consulte também ENTREGA-v0.1.0.md e ENTREGA-v0.2.0.md.

A v0.3.0 prepara RSA/JWKS sem ativação automática. A v0.4.0 implementa veículos, a v0.5.0 motoristas, a v0.6.0 vínculos e a v0.7.0 microfrontends. A ADR 0013 fecha as regras da primeira fatia de abastecimentos; correção/cancelamento continua pendente.
