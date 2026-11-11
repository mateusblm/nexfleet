import { performance } from 'node:perf_hooks';
import { randomUUID } from 'node:crypto';

const HELP = `Uso:
  node quality/load/cq09.mjs [opcoes]

Opcoes:
  --base-url URL       Gateway do NexFleet (padrao: http://127.0.0.1:8080)
  --users N            usuarios virtuais simultaneos (padrao: 100)
  --iterations N       ciclos por usuario (padrao: 3)
  --page-size N        itens solicitados por pagina (padrao: 20)
  --threshold-ms N     limite exclusivo do p95 em ms (padrao: 2000)
  --timeout-ms N       timeout de cada requisicao (padrao: 10000)
  --warmup N           aquecimentos por endpoint (padrao: 2)

Credenciais (variaveis de ambiente obrigatorias):
  NEXFLEET_LOAD_EMAIL
  NEXFLEET_LOAD_PASSWORD
`;

function positiveInteger(name, value, minimum = 1, maximum = Number.MAX_SAFE_INTEGER) {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < minimum || parsed > maximum) {
    throw new Error(`${name} deve ser um inteiro entre ${minimum} e ${maximum}.`);
  }
  return parsed;
}

function readOptions(argv) {
  const options = {
    baseUrl: 'http://127.0.0.1:8080',
    users: 100,
    iterations: 3,
    pageSize: 20,
    thresholdMs: 2000,
    timeoutMs: 10000,
    warmup: 2,
  };
  const names = new Map([
    ['--base-url', 'baseUrl'],
    ['--users', 'users'],
    ['--iterations', 'iterations'],
    ['--page-size', 'pageSize'],
    ['--threshold-ms', 'thresholdMs'],
    ['--timeout-ms', 'timeoutMs'],
    ['--warmup', 'warmup'],
  ]);

  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === '--help' || argument === '-h') {
      process.stdout.write(HELP);
      process.exit(0);
    }
    const property = names.get(argument);
    if (!property || index + 1 >= argv.length) {
      throw new Error(`Opcao desconhecida ou incompleta: ${argument}`);
    }
    options[property] = argv[index + 1];
    index += 1;
  }

  let url;
  try {
    url = new URL(options.baseUrl);
  } catch {
    throw new Error('--base-url deve ser uma URL valida.');
  }
  if (!['http:', 'https:'].includes(url.protocol)) {
    throw new Error('--base-url deve usar HTTP ou HTTPS.');
  }
  options.baseUrl = url.toString().replace(/\/$/, '');
  options.users = positiveInteger('--users', options.users, 1, 1000);
  options.iterations = positiveInteger('--iterations', options.iterations, 1, 1000);
  options.pageSize = positiveInteger('--page-size', options.pageSize, 1, 100);
  options.thresholdMs = positiveInteger('--threshold-ms', options.thresholdMs);
  options.timeoutMs = positiveInteger('--timeout-ms', options.timeoutMs);
  options.warmup = positiveInteger('--warmup', options.warmup, 0, 100);
  return options;
}

function percentile(values, percentileValue) {
  if (values.length === 0) return 0;
  const ordered = [...values].sort((left, right) => left - right);
  const index = Math.max(0, Math.ceil((percentileValue / 100) * ordered.length) - 1);
  return ordered[index];
}

function summarize(records) {
  const durations = records.map((record) => record.durationMs);
  const failed = records.filter((record) => !record.ok);
  return {
    requests: records.length,
    failures: failed.length,
    p50Ms: percentile(durations, 50),
    p95Ms: percentile(durations, 95),
    p99Ms: percentile(durations, 99),
    maxMs: Math.max(0, ...durations),
  };
}

async function request(baseUrl, path, token, timeoutMs) {
  const started = performance.now();
  try {
    const response = await fetch(baseUrl + path, {
      headers: {
        Accept: 'application/json',
        Authorization: `Bearer ${token}`,
        'Cache-Control': 'no-store',
        'X-Correlation-ID': randomUUID(),
      },
      signal: AbortSignal.timeout(timeoutMs),
    });
    await response.arrayBuffer();
    return {
      path: path.split('?')[0],
      status: response.status,
      ok: response.status === 200,
      durationMs: performance.now() - started,
    };
  } catch (error) {
    return {
      path: path.split('?')[0],
      status: 0,
      ok: false,
      error: error instanceof Error ? error.name : 'RequestError',
      durationMs: performance.now() - started,
    };
  }
}

async function login(options, email, password) {
  const response = await fetch(`${options.baseUrl}/api/v1/auth/login`, {
    method: 'POST',
    headers: {
      Accept: 'application/json',
      'Content-Type': 'application/json',
      'X-Correlation-ID': randomUUID(),
    },
    body: JSON.stringify({ email, senha: password }),
    signal: AbortSignal.timeout(options.timeoutMs),
  });
  const body = await response.json().catch(() => ({}));
  if (response.status !== 200 || typeof body.accessToken !== 'string') {
    throw new Error(`Login de teste recusado pelo Gateway (HTTP ${response.status}).`);
  }
  return body.accessToken;
}

async function session(options, token) {
  const response = await fetch(`${options.baseUrl}/api/v1/auth/me`, {
    headers: {
      Accept: 'application/json',
      Authorization: `Bearer ${token}`,
      'X-Correlation-ID': randomUUID(),
    },
    signal: AbortSignal.timeout(options.timeoutMs),
  });
  const body = await response.json().catch(() => ({}));
  if (response.status !== 200 || typeof body.perfil !== 'string') {
    throw new Error(`Sessao de teste invalida (HTTP ${response.status}).`);
  }
  return body;
}

async function main() {
  const options = readOptions(process.argv.slice(2));
  const email = process.env.NEXFLEET_LOAD_EMAIL;
  const password = process.env.NEXFLEET_LOAD_PASSWORD;
  if (!email || !password) {
    throw new Error('Defina NEXFLEET_LOAD_EMAIL e NEXFLEET_LOAD_PASSWORD.');
  }

  process.stdout.write(
    `CQ09: autenticando e preparando ${options.users} usuarios virtuais...\n`,
  );
  const token = await login(options, email, password);
  const currentSession = await session(options, token);
  const endpoints = [
    `/api/v1/veiculos?pagina=0&tamanho=${options.pageSize}`,
    `/api/v1/motoristas?pagina=0&tamanho=${options.pageSize}`,
    `/api/v1/vinculos?pagina=0&tamanho=${options.pageSize}`,
    `/api/v1/abastecimentos?pagina=0&tamanho=${options.pageSize}`,
    `/api/v1/manutencoes?pagina=0&tamanho=${options.pageSize}`,
  ];
  if (currentSession.perfil === 'ADMINISTRADOR') {
    endpoints.unshift(`/api/v1/usuarios?pagina=0&tamanho=${options.pageSize}`);
  }

  for (const endpoint of endpoints) {
    for (let attempt = 0; attempt < options.warmup; attempt += 1) {
      const warmed = await request(options.baseUrl, endpoint, token, options.timeoutMs);
      if (!warmed.ok) {
        throw new Error(`Aquecimento falhou em ${warmed.path} (HTTP ${warmed.status}).`);
      }
    }
  }

  const started = performance.now();
  const users = Array.from({ length: options.users }, (_, userIndex) =>
    (async () => {
      const records = [];
      for (let iteration = 0; iteration < options.iterations; iteration += 1) {
        for (let offset = 0; offset < endpoints.length; offset += 1) {
          const endpoint = endpoints[(userIndex + iteration + offset) % endpoints.length];
          records.push(await request(options.baseUrl, endpoint, token, options.timeoutMs));
        }
      }
      return records;
    })(),
  );
  const records = (await Promise.all(users)).flat();
  const elapsedMs = performance.now() - started;
  const total = summarize(records);
  const byEndpoint = Object.fromEntries(
    endpoints.map((endpoint) => {
      const path = endpoint.split('?')[0];
      return [path, summarize(records.filter((record) => record.path === path))];
    }),
  );
  const thresholdFailures = Object.entries(byEndpoint)
    .filter(([, result]) => result.failures > 0 || result.p95Ms >= options.thresholdMs)
    .map(([path]) => path);
  const approved =
    total.failures === 0 &&
    total.p95Ms < options.thresholdMs &&
    thresholdFailures.length === 0;

  const result = {
    criterion: 'CQ09',
    approved,
    baseUrl: options.baseUrl,
    users: options.users,
    iterationsPerUser: options.iterations,
    pageSize: options.pageSize,
    endpoints: endpoints.length,
    thresholdMs: options.thresholdMs,
    elapsedMs,
    throughputRequestsPerSecond: records.length / (elapsedMs / 1000),
    total,
    byEndpoint,
  };
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);

  if (!approved) {
    throw new Error(
      `CQ09 reprovado: falhas=${total.failures}, p95=${total.p95Ms.toFixed(2)} ms, ` +
        `endpoints fora do limite=${thresholdFailures.join(', ') || 'nenhum'}.`,
    );
  }
  process.stdout.write(
    `CQ09 aprovado: ${records.length} requisicoes, p95 ${total.p95Ms.toFixed(2)} ms ` +
      `(< ${options.thresholdMs} ms), sem erro.\n`,
  );
}

main().catch((error) => {
  process.stderr.write(`ERRO: ${error instanceof Error ? error.message : String(error)}\n`);
  process.exitCode = 1;
});
