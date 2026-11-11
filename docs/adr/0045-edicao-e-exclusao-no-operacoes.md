# ADR 0045 — Edição e exclusão no Operações com eventos versionados

Data: 12/11/2026
Estado: aceita

## Contexto

Até a v1.0.0, abastecimentos e manutenções eram imutáveis (ADRs 0013 e 0017): o Operações só registrava e listava. Um gestor que lançasse um valor errado não tinha como corrigir nem remover o lançamento, e o serviço não oferecia CRUD completo. Os registros alimentam o dashboard do Indicadores por eventos da outbox, então editar ou apagar direto no banco deixaria a projeção com valores errados.

## Decisão

1. **CRUD completo:** `GET`, `PUT` e `DELETE /api/v1/operacoes/{abastecimentos|manutencoes}/{id}` no Operações, expostos pelo BFF em `/api/v1/{abastecimentos|manutencoes}/{id}` e roteados pelo Gateway (que passa a exigir Bearer em todas as rotas desses recursos). Mesmos perfis do registro (ADMINISTRADOR e GESTOR_FROTA); demais recebem 403.
2. **Abastecimento:** o `PUT` aceita só `combustivel`, `litros`, `valorTotal` e `quilometragem`. Data, veículo e motorista ficam fixos, porque dependem do vínculo vigente; para mudá-los, exclui-se e registra-se de novo. A quilometragem nova precisa ficar estritamente entre a do abastecimento anterior e a do seguinte do mesmo veículo (ordem por `realizado_em`, desempate por `id`). O hodômetro é recalculado pelo maior km restante no `PUT` e no `DELETE`, e a linha do hodômetro some quando não sobra abastecimento.
3. **Manutenção:** todos os campos são editáveis com as regras do cadastro, menos o veículo.
4. **Exclusão definitiva** da linha, com rastro no evento (`excluidoPor`, `excluidoEm`) e no log.
5. **Versão por registro:** coluna `versao` (começa em 1) no Operações; cada edição soma 1 e a exclusão publica `versao` atual + 1.
6. **Eventos novos na outbox**, gravados na mesma transação da mudança: `AbastecimentoAtualizado.v1`, `AbastecimentoExcluido.v1`, `ManutencaoAtualizada.v1` e `ManutencaoExcluida.v1`. Os eventos de registro passam a levar `versao: 1` (ausência vale 1). Contratos em `contracts/eventos.asyncapi.yaml`.
7. **Indicadores:** aplica uma atualização só quando a versão é maior que a projetada; a exclusão vira marca (`excluido_em`) que nenhuma versão posterior desfaz, inclusive registro ou atualização que cheguem depois dela. Idempotência por `evento_id`. O dashboard ignora linhas excluídas. As colunas de dados das projeções aceitam NULL para guardar a marca de uma exclusão que chegue antes do registro, com CHECK exigindo dados completos nas linhas não excluídas.
8. **Mensageria:** RabbitMQ local com as routing keys `operacoes.abastecimento.atualizado.v1`, `operacoes.abastecimento.excluido.v1`, `operacoes.manutencao.atualizada.v1` e `operacoes.manutencao.excluida.v1`; na Azure, o filtro `eventos-operacoes-v1` da assinatura `indicadores-v1` inclui os quatro tipos. A notificação por e-mail continua só no `AbastecimentoRegistrado.v1`.
9. **Camada de domínio:** Operações, Indicadores e BFF passam a ter `domain/` nas fatias com regra de negócio (faixa de quilometragem, regras de cadastro, versão, fontes da agregação), com o ArchitectureTest impedindo que `domain` dependa de outra camada ou de framework.

Esta ADR substitui a imutabilidade descrita nas ADRs 0013 (§5) e 0017.

## Consequências

- O `/aggregated-data` e o cálculo de eficiência refletem as correções na hora, porque leem o Operações direto.
- O dashboard corrige-se de forma assíncrona; entre a gravação e o consumo do evento ele pode mostrar o valor anterior por alguns segundos.
- Eventos perdidos antes da v1.1.0 não são reprocessados.
- Não há lixeira nem desfazer: a exclusão é definitiva.

## Alternativas rejeitadas

- **Exclusão lógica:** manteria a linha com um status, mas o "D" do CRUD ficaria discutível e todas as consultas precisariam filtrar o status.
- **Reconstruir a projeção a cada evento lendo o Operações:** acoplaria o Indicadores ao banco ou à API do Operações e perderia o desacoplamento por eventos.
- **Permitir editar data, veículo ou motorista:** exigiria revalidar o vínculo e reordenar o hodômetro de outros registros; excluir e registrar de novo resolve com menos risco.
