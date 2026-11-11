# Evidência CQ06 — validação compreensível dos formulários

Data da execução de referência: 08/11/2026.

## Critério

Quando uma pessoa tenta enviar um formulário inválido, o NexFleet deve:

1. manter os valores válidos já informados;
2. identificar visual e semanticamente os campos inválidos;
3. apresentar uma mensagem que explique como corrigir o preenchimento.

## Implementação

O hook `useFormValidation` usa a validação nativa do HTML e acrescenta a camada de acessibilidade da aplicação:

- `aria-invalid="true"` no controle recusado;
- `aria-describedby` ligando o campo à mensagem;
- aviso com `role="alert"`;
- borda e foco de erro somente depois da tentativa de envio;
- remoção da marcação assim que o campo fica válido;
- preservação do estado React, sem limpar dados corretos.

O comportamento foi aplicado aos sete formulários de entrada:

- login;
- usuários;
- veículos;
- motoristas;
- vínculos;
- abastecimentos;
- manutenções.

Há uma cópia pequena do hook em cada build independente que o utiliza: shell, microfrontend Frota e microfrontend Operações. Isso evita acoplamento de runtime entre os microfrontends; uma futura biblioteca de design compartilhada pode centralizá-lo durante o build.

## Provas automatizadas

| Área | Teste | Resultado observado |
|---|---|---|
| Login | `Login.test.tsx` — `CQ06 marca o campo inválido e preserva o e-mail válido` | E-mail válido permanece; senha obrigatória é marcada; alerta aparece. |
| Usuários | `Usuarios.test.tsx` — `CQ06 mantém o e-mail válido e identifica a senha obrigatória` | E-mail permanece; campo de senha recebe a descrição do erro. |
| Frota | `Veiculos.test.tsx` — `CQ06 preserva a placa válida e marca os campos obrigatórios` | Placa permanece; obrigatórios ausentes são identificados. |
| Operações | `OperacoesApp.test.tsx` — `CQ06 preserva dados válidos e marca o valor obrigatório` | Dados válidos do abastecimento permanecem; valor ausente é marcado. |

Motoristas, vínculos e manutenções usam o mesmo hook e a mesma estilização, além de seus atributos HTML obrigatórios.

## Resultado

Na execução de referência, os quatro projetos frontend aprovaram **47 testes** e geraram os quatro builds Vite. O CQ06 está aprovado no ambiente local.

## Limites

- JSDOM comprova estado, atributos e mensagens, mas não substitui uma sessão exploratória em navegador real.
- Antes da publicação final, devem ser verificados teclado, zoom, contraste e pelo menos um leitor de tela nos navegadores-alvo.
- Erros devolvidos pela API continuam usando as mensagens específicas do backend; esta evidência trata do envio bloqueado pela validação do formulário.
