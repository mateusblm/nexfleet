# Aula 2 — A primeira tela do NexFleet

## O resultado desta etapa

O shell agora tem uma tela técnica para consultar a disponibilidade dos quatro serviços. Ainda não há login, cadastros ou carregamento de microfrontends. Não usamos dados simulados na aplicação; as simulações existem somente nos testes.

## O que é cada peça e por que usamos

- **React:** monta a interface com componentes. Um componente é uma função que descreve uma parte da tela. Nosso primeiro componente é `App`.
- **TypeScript:** identifica erros de tipos durante o desenvolvimento. Por exemplo, impede atribuir um número onde esperamos o nome de um serviço. Ele não valida automaticamente respostas externas; por isso também verificamos o JSON recebido.
- **Vite:** executa o servidor de desenvolvimento e gera os arquivos para publicação. Referência: https://vite.dev/guide/.
- **Shell:** é a aplicação principal que, nas próximas etapas, hospedará os microfrontends. Uma página React sozinha ainda não é uma arquitetura de microfrontends.
- **Estado:** é a memória da tela. `useState` armazena a resposta, se estamos carregando e se ocorreu um erro. Quando o estado muda, React atualiza a interface.

## Como o clique se transforma em informação

1. Você clica em “Verificar ambiente”.
2. `verificar`, em `frontend/src/App.tsx`, limpa o resultado anterior e marca a consulta como em andamento.
3. `consultarAmbiente`, em `frontend/src/ambiente.ts`, chama `/api/v1/ambiente`.
4. Em desenvolvimento, o proxy do Vite encaminha essa chamada para o Gateway na porta 8080. Não chamamos os microsserviços diretamente.
5. O Gateway chama o BFF, que consulta os quatro serviços.
6. A interface valida a resposta e apresenta o resultado. HTTP 503 com o contrato correto significa falha parcial, não necessariamente ausência total de resposta.
7. Em caso de falha de conexão, a tela explica o problema e permite tentar novamente. A consulta tem limite de 30 segundos.

O proxy é uma configuração local, não a configuração final da Azure. Referência: https://vite.dev/config/server-options.html#server-proxy.

## Execute no VS Code

Abra um terminal na raiz do projeto e execute:

```powershell
cd frontend
npm.cmd ci
npm.cmd run dev
```

Abra `http://127.0.0.1:5173`. Mantenha esse terminal aberto; Ctrl+C encerra o servidor.

A página abre sem Docker. Para receber informações reais, o backend da Aula 1 precisa estar funcionando na porta 8080. Sem ele, a mensagem de indisponibilidade é esperada — não representa um cadastro ou um ambiente simulado.

Se você mudou `GATEWAY_PORT`, ajuste também o destino do proxy em `frontend/vite.config.ts`.

## Testar não é só abrir a tela

Em outro terminal, dentro de `frontend`:

```powershell
npm.cmd test
npm.cmd run build
```

Os testes verificam a interação e as respostas usando um servidor simulado em memória. Não comprovam conectividade com bancos reais. O build verifica os tipos e gera `dist`, os arquivos estáticos para futura publicação. Nunca coloque senhas de banco no frontend: seus arquivos são enviados ao navegador.

## Exercício guiado

1. Abra `frontend/src/App.tsx` e localize o título “Vamos conectar sua frota.”.
2. Altere o texto e salve. Observe a atualização no navegador.
3. Localize os três `useState` e explique qual informação cada um guarda.
4. Clique em verificar. Observe a mensagem quando o backend está desligado.
5. Com o backend ativo, repita e confira os quatro serviços.

Avance somente depois de conseguir explicar a diferença entre interface, Gateway e BFF. Os próximos passos são executar o caminho completo com Docker e incorporar os microfrontends, sem começar regras de cadastro ainda.
