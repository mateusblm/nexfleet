# Aula 9 — Cadastro de motoristas com dados protegidos

## O que foi construído

RF06 e RF07 viraram uma segunda fatia vertical de Frota:

```text
Tela → /api/v1/motoristas → Gateway → BFF → /api/v1/frota/motoristas → Frota → PostgreSQL Frota
```

A tela cadastra, lista, filtra e edita nome, CPF, CNH, categoria, validade, telefone e status. CPF e CNH ficam únicos no banco. A listagem mascara esses documentos para reduzir exposição visual.

## Por que não reutilizar um CRUD genérico

Veículos e motoristas parecem formulários parecidos, mas protegem regras diferentes. Veículo normaliza placa e possui inativação própria. Motorista normaliza CPF/CNH, trata dados pessoais e fornece validade da habilitação para o futuro vínculo. Um CRUD genérico esconderia essas diferenças importantes.

## Como Clean Architecture aparece

- `GerenciarMotoristas` valida e normaliza os dados sem importar Spring ou JDBC.
- `Motoristas` é a porta de persistência conhecida pelo caso de uso.
- `JdbcMotoristas` contém o SQL e traduz violações únicas para conflito 409.
- `MotoristasController` traduz HTTP/JWT, mas não executa SQL.
- Os testes ArchUnit impedem que domínio e aplicação dependam das camadas externas.

Vertical Slice aparece porque API, aplicação e infraestrutura estão agrupadas em `gerenciarmotoristas`, formando uma capacidade completa.

## Como executar

Use o mesmo ambiente RSA/JWKS da Aula 8. Depois do login, abra **Gerenciar motoristas**. CPF pode ser digitado com pontuação; Frota grava apenas os onze dígitos. CNH exige onze dígitos.

## Regras cobertas

- nome, CPF, CNH, categoria, validade, telefone e status obrigatórios;
- CPF e CNH normalizados e únicos;
- estados `ATIVO` e `INATIVO`;
- consulta paginada e filtro por status;
- Administrador ou Gestor autenticado;
- CPF e CNH mascarados na lista e ausentes dos logs da aplicação.

## Evolução na v0.6.0

RF08 agora cria vínculos históricos. O cadastro continua aceitando validade passada porque registros históricos não podem sumir, mas a criação de um novo vínculo recusa motorista inativo ou com CNH vencida. A política de simultaneidade e encerramento está na ADR 0011 e na Aula 10.

## Quando usar esse padrão

Use essa separação quando os dados possuem regras e sensibilidade próprias. Validação de entrada melhora a mensagem ao usuário; restrições únicas no PostgreSQL continuam necessárias para proteger concorrência e qualquer outro cliente da API.
