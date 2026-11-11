# ADR 0025 — feedback de validação acessível para CQ06

- Status: aceita.
- Data: 08/11/2026.
- Escopo: Sprint 4, v0.20.0.

## Contexto

Os formulários já declaravam restrições HTML, mas o navegador podia indicar somente o primeiro erro e cada tela tratava a experiência de modo diferente. O CQ06 exige preservar dados válidos, marcar campos incorretos e apresentar uma mensagem compreensível.

## Decisão

Cada build React que contém formulários passa a ter um hook `useFormValidation`. O hook observa os eventos `invalid` e `input` do formulário, mantém a validação nativa e acrescenta estado visual e semântico com `aria-invalid`, `aria-describedby` e um alerta textual.

O hook não copia valores nem reinicializa o formulário. Os campos continuam controlados pelo componente existente, portanto uma tentativa inválida não apaga o preenchimento correto. A classe `validacao-exibida` só é acrescentada depois da tentativa de envio para não apresentar a tela inteira como errada antes da interação.

## Alternativas consideradas

- **Depender apenas do balão nativo do navegador**: simples, porém inconsistente entre navegadores e insuficiente para um resumo de erro acessível.
- **Adicionar uma biblioteca de formulários**: ofereceria mais recursos, mas aumentaria dependências e exigiria reescrever telas estáveis para um comportamento pequeno.
- **Criar agora um pacote compartilhado de UI**: reduziria repetição, mas também criaria acoplamento de build entre os microfrontends nesta etapa.

## Consequências

- Os sete formulários apresentam o mesmo feedback.
- A validação permanece compatível com as restrições HTML existentes.
- Quatro testes de aceitação protegem os fluxos representativos.
- O hook e o CSS possuem pequenas duplicações entre três builds; uma biblioteca compartilhada pode ser avaliada quando houver mais componentes comuns.

Veja a [Evidência CQ06](../EVIDENCIA-CQ06-USABILIDADE.md), a [Aula 24](../tutorials/24-validacao-acessivel-cq06.md) e a [matriz CQ01–CQ12](../MATRIZ-CQ01-CQ12.md).
