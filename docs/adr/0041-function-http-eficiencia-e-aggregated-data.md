# ADR 0041 — Function HTTP `calcular-eficiencia` e `GET /aggregated-data` no BFF

Data: 11/11/2026
Estado: aceita

## Contexto

O enunciado final exige que o BFF exponha `GET /aggregated-data`, combinando dados de **dois microsserviços** e de uma **Azure Function HTTP**. Até a v0.30.0, a única Function (`NotificarAbastecimento`) era acionada por evento e o BFF compunha apenas o dashboard (ADR 0018).

Também era preciso que a visão consolidada continuasse útil quando uma das fontes falhasse, e que a Function não ficasse aberta a abuso, porque o endpoint de uma Function é público.

## Decisão

### Function `CalcularEficiencia`

1. Nova fatia `calculareficiencia` (`api/`, `application/`, `domain/`) no mesmo Function App da notificação. Rota `POST /api/calcular-eficiencia`, `authLevel = FUNCTION`: sem a chave da função, o próprio runtime responde 401.
2. **Sem estado e sem banco.** A entrada é a lista de veículos com abastecimentos (`data`, `litros`, `valor`, `quilometragem`) e manutenções (`valor`). A saída traz, por veículo e para a frota, consumo médio (km/l), custo por km, gasto total e distância.
3. **Regras de cálculo** (`CalculadoraEficiencia`): distância = km máximo − km mínimo; consumo = distância ÷ litros dos abastecimentos posteriores ao primeiro; custo por km = (gasto com abastecimentos + manutenções) ÷ distância. Com menos de dois abastecimentos, consumo e custo por km vêm `null` e o gasto total é calculado. Valores com duas casas, arredondamento `HALF_EVEN`.
4. **Entrada inválida → 400** sem calcular: JSON malformado, valores negativos ou mais de **10.000 itens** (`CalcularEficiencia.LIMITE_ITENS`). O teto cobre os 4.000 abastecimentos e 4.000 manutenções que o BFF envia, mais os veículos.
5. Lê `X-Correlation-ID` (só UUID canônico; ausente ou inválido vira um UUID novo), registra-o nos logs e o devolve (ADR 0021).

### BFF `GET /aggregated-data`

1. Nova fatia `consultaragregado` com três portas (`FrotaAgregadaRemota`, `OperacoesAgregadasRemotas`, `EficienciaRemota`). O BFF não acessa banco: reaproveita os clientes HTTP de Frota e Operações. Rotas `GET /aggregated-data` e `GET /api/v1/aggregated-data`, registradas também no Gateway e na API raiz do APIM. Exigem o mesmo JWT das demais rotas; sem token, 401.
2. **Resposta:** `frota`, `operacoes` (os 10 registros mais recentes de cada histórico e o campo `truncado`), `eficiencia`, `fontes` e `geradoEm`. Contrato em `contracts/aggregated-data.openapi.yaml`.
3. **Retorno parcial:** cada fonte tem o próprio tempo limite (`AGREGADO_TIMEOUT`, padrão 5 s). Se uma fonte falha ou estoura o tempo, a resposta é 200 com a seção vazia e `fontes.<fonte> = "falhou"`, e o BFF registra `agregacao_fonte_falhou` com a fonte e o motivo (só o tipo do erro). Se as três falharem, a resposta é 502.
4. **Ordem das chamadas:** Frota e Operações começam juntas, em threads virtuais. A Function **depende** do histórico de Operações (e das placas de Frota): só é chamada depois que as duas terminam. Se Operações falhar, a Function nem é chamada e `fontes.funcao` vem `"falhou"`. Dentro de cada fonte, as páginas são lidas em sequência (100 itens por página).
5. **Limites de leitura:** Operações até **4.000** abastecimentos e **4.000** manutenções (`OperacoesPorServicos.LIMITE_POR_HISTORICO`). Acima disso, o BFF corta, registra aviso e devolve `operacoes.truncado = true`. Na Frota, cada lista (veículos, motoristas, vínculos) é lida até 10 páginas de 100.
6. A URL da Function chega por `EFICIENCIA_FUNCTION_URL` (só a base; o BFF acrescenta `/api/calcular-eficiencia`) e a chave por `EFICIENCIA_FUNCTION_KEY`, secret do Container App do BFF.

### Painel

O microfrontend Painel ganhou o cartão "Visão consolidada", que chama `/api/v1/aggregated-data`, mostra consumo médio e custo por km por veículo e exibe aviso legível quando `fontes` indica falha.

## Consequências

- **Tempo sequencial:** como a Function só começa depois de Operações, o pior caso de `GET /aggregated-data` é a soma de dois tempos limite (cerca de 10 s com o padrão de 5 s), não um só. E como as páginas de cada fonte são lidas em sequência dentro do mesmo limite, um histórico grande (até cerca de 80 páginas pedidas a Operações) pode estourar os 5 s e marcar `operacoes` (e, por consequência, `funcao`) como `"falhou"`, mesmo com o serviço saudável.
- A spec previa as três chamadas em paralelo; o paralelismo vale só entre Frota e Operações, porque a entrada da Function é derivada delas.
- Uma falha da Function não afeta `frota` e `operacoes`, que vêm preenchidas normalmente.
- A chave da Function só existe no BFF; um terceiro sem a chave recebe 401, e um corpo acima de 10.000 itens recebe 400.
- O cálculo é refeito a cada chamada, sem cache. Para o volume acadêmico, isso é aceitável.

## Alternativas rejeitadas

- **Function lendo o banco de Operações:** violaria a regra de banco por serviço (ADR 0040) e daria à Function uma credencial a mais.
- **Calcular a eficiência no próprio BFF:** não atenderia ao requisito de uma Function HTTP na composição.
- **Responder 502 quando qualquer fonte falha:** tornaria a tela inteira indisponível por causa de uma fonte.
