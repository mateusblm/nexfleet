# Aula 10 — Vínculos históricos

## O que foi construído

Esta fatia liga um motorista a um veículo e preserva cada período do relacionamento. A tela cria, lista por veículo e encerra vínculos. Encerrar não exclui: apenas registra o horário final e mantém a linha para consultas futuras.

O percurso continua completo: React → Gateway → BFF → Frota → PostgreSQL. Essa organização é uma fatia vertical porque uma capacidade visível atravessa todas as camadas sem misturar suas responsabilidades.

## Por que existe uma tabela própria

Guardar apenas `motorista_id` no veículo perderia o motorista anterior a cada troca. `veiculo_motorista` possui início e fim, então uma consulta consegue reconstruir o histórico. As chaves estrangeiras são válidas porque veículo, motorista e vínculo pertencem ao mesmo banco Frota; nunca há chave estrangeira entre microsserviços.

## Como as regras são protegidas

- O caso de uso recusa veículo inativo.
- O motorista precisa estar ativo e sua CNH não pode estar vencida na data de criação.
- O caso de uso fornece mensagens claras antes da gravação.
- Um índice único parcial no PostgreSQL garante no máximo uma linha sem `fim_em` para cada veículo, inclusive em concorrência.
- O encerramento usa o horário do servidor e registra o usuário responsável.

A validação na aplicação ajuda o usuário. A restrição no banco protege os dados quando duas requisições chegam quase ao mesmo tempo. As duas são necessárias.

## Decisões para as lacunas do PJBL

O documento não proíbe um motorista de dirigir veículos diferentes simultaneamente; portanto, não adicionamos essa restrição. CNH vencida bloqueia apenas novos vínculos e não apaga histórico. Administrador e Gestor podem encerrar um vínculo, sempre no instante atual; não há data retroativa nesta versão.

## Como Clean Architecture aparece

- `GerenciarVinculos` contém autorização e regras sem importar Spring ou JDBC.
- `Vinculos` é a porta conhecida pela aplicação.
- `JdbcVinculos` implementa persistência, junções e tradução da restrição única.
- `VinculosController` traduz HTTP e JWT.
- O BFF conhece apenas o contrato REST público de Frota.

## Como testar

Os testes de domínio usam um relógio fixo, evitando resultados diferentes conforme o dia. Eles cobrem referências inativas, CNH vencida, vínculo duplicado e encerramento repetido. Testes HTTP verificam JWT e ausência de CSRF; BFF e Gateway comprovam o encaminhamento; React verifica criação, histórico e encerramento.

## Quando usar este padrão

Use uma entidade temporal quando o relacionamento muda, mas o passado precisa permanecer consultável. Não use exclusão física para informações que participarão de auditoria, abastecimentos ou indicadores.
