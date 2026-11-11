# Aula 24 — validação acessível e preservação dos dados

## 1. O problema

Um atributo como `required` impede o envio vazio, mas não garante sozinho uma experiência uniforme. O usuário precisa saber o que corrigir sem perder aquilo que já preencheu corretamente.

## 2. Estado controlado preserva valores

Nos formulários do NexFleet, cada valor pertence ao estado React. Quando o navegador dispara `invalid`, o formulário não é enviado e nenhum estado é reinicializado. Assim, placa, e-mail, quilometragem e demais valores válidos permanecem na tela.

O estado só deve ser limpo depois de uma resposta de sucesso. Erro de validação local ou resposta de erro da API não deve apagar o trabalho da pessoa.

## 3. O hook comum

`useFormValidation` escuta os eventos no próprio `<form>`:

```tsx
const validacao = useFormValidation("veiculo-validacao");

<form
  className={validacao.className("formulario")}
  onInvalid={validacao.onInvalid}
  onInput={validacao.onInput}
  onSubmit={salvar}
>
```

Como o evento percorre a árvore, não é necessário repetir um manipulador em cada campo. O elemento inválido recebe:

```text
aria-invalid="true"
aria-describedby="identificador-da-mensagem"
```

A mensagem possui `role="alert"`, permitindo que tecnologia assistiva anuncie a correção necessária.

## 4. Feedback visual no momento correto

A classe `validacao-exibida` só aparece depois da primeira tentativa inválida. O CSS então seleciona controles `:invalid` e aplica borda e foco de erro. Enquanto a pessoa apenas está começando a digitar, o formulário não mostra todos os obrigatórios como falhas.

Quando um campo se torna válido, o hook remove `aria-invalid`. Quando não existe mais nenhum `:invalid`, o resumo desaparece.

## 5. Como testar

Um bom teste do CQ06 precisa verificar comportamento, não apenas a presença do atributo `required`:

1. preencher um campo com valor válido;
2. deixar outro obrigatório vazio;
3. tentar enviar;
4. confirmar que o valor correto permaneceu;
5. confirmar `aria-invalid` e `aria-describedby` no campo incorreto;
6. confirmar a mensagem com papel de alerta.

O projeto aplica esse modelo em login, usuários, veículos e abastecimentos. Os mesmos componentes de validação atendem motoristas, vínculos e manutenções.

## 6. Executar a prova

Na raiz do projeto:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\scripts\Test-Project.ps1" -SkipInstall
```

Consulte também a [ADR 0025](../adr/0025-validacao-acessivel-cq06.md), a [Evidência CQ06](../EVIDENCIA-CQ06-USABILIDADE.md) e a [matriz CQ01–CQ12](../MATRIZ-CQ01-CQ12.md).
