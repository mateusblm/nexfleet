# ADR 0010 — Cadastro de motoristas no serviço Frota

- Status: aceito
- Data: 23/10/2026

## Contexto

RF06 e RF07 exigem cadastrar, editar e consultar motoristas com nome, CPF, CNH, categoria, validade, telefone e status. RB04 exige CPF e CNH únicos. Esses documentos são dados pessoais e não devem aparecer em logs ou em telas sem necessidade.

## Decisão

Frota é dona de `frota.motorista`. A migração V3 adiciona a tabela sem alterar `frota.veiculo`. CPF e CNH são normalizados para onze dígitos e possuem restrições únicas independentes. O serviço armazena também os UUIDs de auditoria, sem chave estrangeira para Identidade.

Administrador e Gestor de Frota podem criar, consultar e editar motoristas conforme a matriz de permissões vigente. Não há rota de exclusão: RF07 não a solicita e o estado `INATIVO` é alterado por edição. A interface mascara CPF e CNH na listagem; o transporte continua protegido por autenticação e não registra esses valores em logs.

Uma CNH vencida pode permanecer cadastrada, pois históricos precisam ser preservados. A validade será exigida quando um novo vínculo for criado por RF08/RB07. Não foi adicionada validação matemática de CPF ou CNH porque o PJBL exige presença e unicidade, não integração com fonte oficial.

## Consequências

- RF06, RF07 e RB04 passam a ter implementação executável.
- A migração é aditiva; um rollback de aplicativo preserva a tabela e seus dados.
- Vínculos, encerramento automático por vencimento e simultaneidade continuam fora deste recorte até decisão própria.
- O próximo caso de uso pode consultar motorista ativo e validade sem acessar diretamente o banco de outro serviço.
