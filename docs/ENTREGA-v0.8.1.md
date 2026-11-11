# Entrega v0.8.1 — pacote portátil

Esta versão organiza o NexFleet para ser transferido e executado em outra máquina sem incluir credenciais ou artefatos gerados.

## Alterações desta versão

- README reescrito com os requisitos e o fluxo completo de primeira execução.
- Inicialização automática de `.env.sprint0` com segredos locais aleatórios.
- Geração de chave RSA compatível com Windows PowerShell 5.1 e PowerShell 7.
- Comando único para iniciar e validar o backend local.
- Provisionamento opcional e explícito do primeiro usuário.
- Comando seguro para parar o ambiente sem apagar os volumes.
- Comando centralizado para executar os testes Java e JavaScript.

## Arquivos locais que não acompanham o ZIP

- `.env.sprint0`: contém senhas e segredos da máquina de origem.
- `.secrets/`: contém a chave privada RSA da máquina de origem.
- `node_modules/`, `target/` e `dist/`: são recriados durante instalação, teste ou build.

## Validação da entrega

- Scripts analisados pelo parser do PowerShell.
- Inicialização testada em uma pasta isolada.
- Stack validada com dez contêineres saudáveis.
- Fluxo Gateway → BFF → quatro serviços → respectivos bancos validado.
- ZIP extraído e inspecionado em uma pasta temporária antes da entrega.

As funcionalidades continuam sendo as descritas em `ENTREGA-v0.8.0.md`. A versão 0.8.1 é uma atualização de empacotamento, documentação e automação local.
