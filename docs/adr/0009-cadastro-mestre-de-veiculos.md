# ADR 0009 — Cadastro mestre de veículos no serviço Frota

- Status: aceito
- Data: 23/10/2026

## Contexto

RF04, RF05 e RF15 exigem cadastrar, alterar, consultar, filtrar e desativar veículos. RB03 exige placa única. Históricos de vínculos e operações não podem desaparecer quando um veículo sai de uso. Identidade e Frota possuem bancos separados.

## Decisão

O serviço Frota é dono de `frota.veiculo`. A tabela guarda placa normalizada em maiúsculas, atributos cadastrais, quilometragem inicial/projetada, status, data de aquisição e UUIDs de auditoria. O UUID do autor não é chave estrangeira: pertence ao serviço Identidade.

`DELETE` representa inativação lógica, alterando o status para `INATIVO`; não remove linha. Placa permanece única inclusive após a inativação, evitando reutilização ambígua em históricos. Administrador e Gestor de Frota podem operar o cadastro conforme a ADR 0002 vigente.

O BFF expõe o contrato da interface e encaminha o Bearer. Frota valida assinatura, emissor, audiência, expiração e perfil pelo JWKS de Identidade. Endpoints de veículo ficam fechados quando o perfil `jwt-rsa` não está ativo.

## Consequências

- RF04, RF05, RF15 e RB03 passam a ter implementação executável.
- RB05 será aplicada novamente nos futuros casos de vínculo, abastecimento e manutenção; cadastro sozinho não prova essa regra.
- A migração V2 é aditiva e pode ser revertida antes de dados reais com `DROP TABLE`; depois de uso, o rollback seguro é voltar o código mantendo a tabela.
- Quilometragem operacional continuará sendo fonte da verdade em Operações. O campo atual em Frota servirá como projeção quando EDA for implementada.
