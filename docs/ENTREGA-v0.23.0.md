# Entrega v0.23.0 — indisponibilidade e log seguro CQ07

Data: 08/11/2026.

## Resultado

A nona fatia da Sprint 4 aprova CQ07 localmente. O serviço Frota real é executado com PostgreSQL efêmero; depois da parada controlada desse banco, readiness e API técnica respondem `DOWN/503`. O log preserva a correlação sem expor a senha ou o token sentinela.

## Entregas

- `Test-Cq07.ps1` com rede, banco, serviço, porta e credenciais efêmeros;
- readiness `UP/200` antes da falha e `DOWN/503` depois dela;
- consulta técnica `DOWN/503` ligada ao mesmo `X-Correlation-ID` da resposta e do log;
- inspeção negativa de senha de banco e token Bearer nos logs;
- inclusão da prova em `Test-Project.ps1 -IncludeDatabaseIntegration`;
- execução CQ07 no workflow backend;
- ADR 0028, Aula 27 e relatório de evidência.

## Verificação

- CQ07: cenário integrado aprovado;
- qualidade documental/contratual: 3 testes aprovados;
- sintaxe de todos os scripts PowerShell e links locais da documentação aprovados;
- bancos, serviços ou volumes ativos alterados: nenhum;
- contêineres e redes temporários restantes: nenhum.

## O que permanece aberto

Todos os CQ01–CQ12 possuem evidência local; CQ09 e CQ10 ainda precisam ser repetidos na homologação Azure. Permanecem também revisão final de C4/UML/DER, decisão do provedor externo de notificações e publicação HTTPS com custos, segredos e backup gerenciado aprovados.

Veja a [Evidência CQ07](EVIDENCIA-CQ07-INDISPONIBILIDADE.md), a [matriz CQ01–CQ12](MATRIZ-CQ01-CQ12.md) e o [estado das sprints](STATUS-SPRINTS.md).
