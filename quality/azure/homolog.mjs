// Homologacao Azure (etapa 6): percorre o fluxo critico pela borda publica (APIM HTTPS).
// Credenciais chegam por NEXFLEET_HOMOLOG_EMAIL/NEXFLEET_HOMOLOG_PASSWORD; nada sensivel e impresso.
// Cria dados identificaveis pelo prefixo HML para preservar a rastreabilidade do ensaio.
const base = (process.env.NEXFLEET_HOMOLOG_URL ?? "").replace(/\/$/, "");
const email = process.env.NEXFLEET_HOMOLOG_EMAIL;
const senha = process.env.NEXFLEET_HOMOLOG_PASSWORD;
if (!base.startsWith("https://") || !email || !senha) {
  console.error("Defina NEXFLEET_HOMOLOG_URL (https), NEXFLEET_HOMOLOG_EMAIL e NEXFLEET_HOMOLOG_PASSWORD.");
  process.exit(2);
}

const resultados = [];
function registrar(id, ok, detalhe) {
  resultados.push({ id, ok, detalhe });
  console.log(`${ok ? "OK  " : "FALHA"} ${id}: ${detalhe}`);
}

async function chamar(metodo, caminho, { token, corpo, tentativas = 6, idempotente = metodo === "GET" } = {}) {
  let ultimoErro;
  for (let tentativa = 1; tentativa <= tentativas; tentativa++) {
    try {
      const inicio = performance.now();
      const resposta = await fetch(base + caminho, {
        method: metodo,
        headers: {
          ...(corpo ? { "Content-Type": "application/json" } : {}),
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
          "X-Correlation-Id": crypto.randomUUID(),
        },
        body: corpo ? JSON.stringify(corpo) : undefined,
        signal: AbortSignal.timeout(60000),
      });
      const texto = await resposta.text();
      // 502/503/504: escala a partir de zero (Identidade, Frota e BFF usam minReplicas 0).
      // Somente leituras sao repetidas: um POST pode ter gravado antes do timeout da borda.
      if ([502, 503, 504].includes(resposta.status) && idempotente && tentativa < tentativas) {
        await new Promise((r) => setTimeout(r, 5000 * tentativa));
        continue;
      }
      let json = null;
      try { json = texto ? JSON.parse(texto) : null; } catch { json = null; }
      return { status: resposta.status, json, ms: Math.round(performance.now() - inicio) };
    } catch (erro) {
      ultimoErro = erro;
      await new Promise((r) => setTimeout(r, 5000 * tentativa));
    }
  }
  throw new Error(`${metodo} ${caminho} falhou: ${ultimoErro?.message ?? "tentativas esgotadas"}`);
}

const sufixo = Date.now().toString().slice(-7);

// CQ01: API protegida sem sessao.
const semToken = await chamar("GET", "/api/v1/veiculos?pagina=0&tamanho=5");
registrar("CQ01 sem token", semToken.status === 401, `HTTP ${semToken.status}`);

// RF01: login por HTTPS e sessao com perfil.
// Login nao grava estado: pode ser repetido durante a troca de revisao ou escala a partir de zero.
const login = await chamar("POST", "/api/v1/auth/login", { corpo: { email, senha }, idempotente: true, tentativas: 10 });
const token = login.json?.accessToken;
registrar("RF01 login", login.status === 200 && typeof token === "string", `HTTP ${login.status} em ${login.ms} ms`);
if (!token) {
  console.log(JSON.stringify({ aprovado: false, resultados }));
  process.exit(1);
}
const me = await chamar("GET", "/api/v1/auth/me", { token });
registrar("RF03 perfil", me.status === 200 && me.json?.perfil === "ADMINISTRADOR", `HTTP ${me.status}, perfil ${me.json?.perfil}`);

// Aquecimento fora da prova: acorda os servicos com minReplicas 0 antes das escritas.
for (const lista of ["veiculos", "motoristas", "vinculos", "abastecimentos", "manutencoes"]) {
  await chamar("GET", `/api/v1/${lista}?pagina=0&tamanho=1`, { token, tentativas: 10 });
}
await chamar("GET", "/api/v1/dashboard", { token, tentativas: 10 });

// RF02: Administrador cadastra um Gestor de Frota.
const gestor = await chamar("POST", "/api/v1/usuarios", {
  token,
  corpo: { email: `gestor.hml.${sufixo}@example.com`, senha: `Hml-${crypto.randomUUID()}`, perfil: "GESTOR_FROTA" },
});
registrar("RF02 usuario gestor", gestor.status === 201, `HTTP ${gestor.status}`);

// RF04: cadastro de veiculo.
const hoje = new Date().toISOString().slice(0, 10);
const veiculo = await chamar("POST", "/api/v1/veiculos", {
  token,
  corpo: {
    placa: `HML${sufixo.slice(-4)}`,
    marca: "Homologacao",
    modelo: "Azure",
    ano: 2024,
    tipo: "Utilitario",
    quilometragem: 1000,
    status: "DISPONIVEL",
    dataAquisicao: hoje,
  },
});
registrar("RF04 veiculo", veiculo.status === 201, `HTTP ${veiculo.status}`);

// RF06: cadastro de motorista (CPF/CNH com 11 digitos unicos por execucao).
const documento = (prefixo) => (prefixo + sufixo + "0000000000").slice(0, 11);
const validade = new Date(Date.now() + 365 * 86400000).toISOString().slice(0, 10);
const motorista = await chamar("POST", "/api/v1/motoristas", {
  token,
  corpo: {
    nome: `Motorista HML ${sufixo}`,
    cpf: documento("9"),
    cnh: documento("8"),
    categoria: "B",
    validadeCnh: validade,
    telefone: "41 0000-0000",
    status: "ATIVO",
  },
});
registrar("RF06 motorista", motorista.status === 201, `HTTP ${motorista.status}`);

// RF08: vinculo exigido para abastecer.
const vinculo = await chamar("POST", "/api/v1/vinculos", {
  token,
  corpo: { veiculoId: veiculo.json?.id, motoristaId: motorista.json?.id },
});
registrar("RF08 vinculo", vinculo.status === 201, `HTTP ${vinculo.status}`);

// A data precisa estar dentro do vinculo e nao no futuro do servidor: usa o relogio do
// servidor (inicio do vinculo) em vez do relogio local, que pode divergir.
const realizadoEm = new Date(Date.parse(vinculo.json?.inicio ?? new Date().toISOString()) + 1000).toISOString();
await new Promise((r) => setTimeout(r, 3000));

// RF09/RF10: abastecimento valido -> outbox -> Service Bus -> Indicadores e Function (e-mail).
const abastecimento = await chamar("POST", "/api/v1/abastecimentos", {
  token,
  corpo: {
    veiculoId: veiculo.json?.id,
    motoristaId: motorista.json?.id,
    realizadoEm,
    combustivel: "GASOLINA",
    litros: 42.5,
    valorTotal: 255.75,
    quilometragem: 1250,
  },
});
registrar("RF09 abastecimento", abastecimento.status === 201, `HTTP ${abastecimento.status}`);

// CQ03: quilometragem abaixo do hodometro atual (1250) recusada sem gravacao.
const regressivo = await chamar("POST", "/api/v1/abastecimentos", {
  token,
  corpo: {
    veiculoId: veiculo.json?.id,
    motoristaId: motorista.json?.id,
    realizadoEm,
    combustivel: "GASOLINA",
    litros: 10,
    valorTotal: 60,
    quilometragem: 1100,
  },
});
registrar("CQ03 km regressivo", regressivo.status === 422, `HTTP ${regressivo.status}`);

// RF11: historico por veiculo.
const historico = await chamar("GET", `/api/v1/abastecimentos?veiculoId=${veiculo.json?.id}&pagina=0&tamanho=5`, { token });
registrar(
  "RF11 historico",
  historico.status === 200 && Array.isArray(historico.json) && historico.json.length === 1 &&
    historico.json[0].id === abastecimento.json?.id,
  `HTTP ${historico.status}, ${Array.isArray(historico.json) ? historico.json.length : 0} registro(s); regressivo nao gravado`,
);

// RF14: dashboard atualizado por evento (consistencia eventual via Service Bus).
let dashboard;
let refletiu = false;
for (let i = 0; i < 12 && !refletiu; i++) {
  dashboard = await chamar("GET", "/api/v1/dashboard", { token });
  refletiu = dashboard.status === 200 && JSON.stringify(dashboard.json ?? {}).includes("255.75");
  if (!refletiu) await new Promise((r) => setTimeout(r, 10000));
}
registrar("RF14 dashboard por evento", refletiu, `HTTP ${dashboard?.status}${refletiu ? ", custo refletido" : ", custo ainda nao refletido"}`);

const aprovado = resultados.every((r) => r.ok);
console.log(JSON.stringify({
  aprovado,
  executadoEm: new Date().toISOString(),
  abastecimentoId: abastecimento.json?.id ?? null,
  resultados,
}));
process.exit(aprovado ? 0 : 1);
