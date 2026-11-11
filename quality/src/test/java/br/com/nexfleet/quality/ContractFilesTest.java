package br.com.nexfleet.quality;

import static org.junit.jupiter.api.Assertions.*;

import java.io.IOException;
import java.io.InputStream;
import java.net.URI;
import java.nio.file.*;
import java.util.*;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;
import org.yaml.snakeyaml.LoaderOptions;
import org.yaml.snakeyaml.Yaml;

class ContractFilesTest {
  private static final Set<String> HTTP_METHODS =
      Set.of("get", "post", "put", "patch", "delete", "head", "options", "trace");
  private static final Pattern PATH_PARAMETER = Pattern.compile("\\{([^}]+)}");
  private static final Set<String> PUBLIC_ROUTES =
      Set.of(
          "GET /api/v1/ambiente",
          "POST /api/v1/auth/login",
          "GET /api/v1/auth/me",
          "GET /api/v1/usuarios",
          "POST /api/v1/usuarios",
          "GET /api/v1/usuarios/{id}",
          "PUT /api/v1/usuarios/{id}",
          "DELETE /api/v1/usuarios/{id}",
          "GET /api/v1/veiculos",
          "POST /api/v1/veiculos",
          "GET /api/v1/veiculos/{id}",
          "PUT /api/v1/veiculos/{id}",
          "DELETE /api/v1/veiculos/{id}",
          "GET /api/v1/motoristas",
          "POST /api/v1/motoristas",
          "GET /api/v1/motoristas/{id}",
          "PUT /api/v1/motoristas/{id}",
          "GET /api/v1/vinculos",
          "POST /api/v1/vinculos",
          "PUT /api/v1/vinculos/{id}/encerramento",
          "GET /api/v1/abastecimentos",
          "POST /api/v1/abastecimentos",
          "GET /api/v1/manutencoes",
          "POST /api/v1/manutencoes",
          "GET /api/v1/dashboard");

  @Test
  void contratosOpenApiSaoCompletosECoerentes() throws IOException {
    Path contracts = contractsDirectory();
    List<Path> files;
    try (Stream<Path> paths = Files.list(contracts)) {
      files = paths
          .filter(path -> path.getFileName().toString().endsWith(".openapi.yaml"))
          .sorted()
          .toList();
    }

    assertEquals(10, files.size(), "Quantidade inesperada de contratos OpenAPI.");
    Set<String> operationIds = new HashSet<>();
    Set<String> publicRoutes = new TreeSet<>();

    for (Path file : files) {
      Map<String, Object> document = load(file);
      String label = file.getFileName().toString();
      assertTrue(string(document, "openapi").startsWith("3."), label);
      Map<String, Object> info = map(document, "info");
      assertFalse(string(info, "title").isBlank(), label);
      assertFalse(string(info, "version").isBlank(), label);
      Map<String, Object> paths = map(document, "paths");
      assertFalse(paths.isEmpty(), label);
      validateLocalReferences(document, document, label);

      boolean internal = label.equals("identidade.openapi.yaml");
      String serverPrefix = serverPrefix(document);
      for (Map.Entry<String, Object> pathEntry : paths.entrySet()) {
        String path = pathEntry.getKey();
        Map<String, Object> pathItem = castMap(pathEntry.getValue(), label + " " + path);
        for (Map.Entry<String, Object> entry : pathItem.entrySet()) {
          String method = entry.getKey().toLowerCase(Locale.ROOT);
          if (!HTTP_METHODS.contains(method)) continue;
          Map<String, Object> operation =
              castMap(entry.getValue(), label + " " + method + " " + path);
          String operationId = string(operation, "operationId");
          assertFalse(operationId.isBlank(), label + " " + method + " " + path);
          assertTrue(operationIds.add(operationId), "operationId duplicado: " + operationId);
          validateResponses(operation, label, method, path);
          validatePathParameters(pathItem, operation, path, label, method);
          validateSecurity(document, operation, resolvedPath(serverPrefix, path), label, method);
          if (!internal) {
            publicRoutes.add(method.toUpperCase(Locale.ROOT) + " " + resolvedPath(serverPrefix, path));
          }
        }
      }
    }

    assertEquals(PUBLIC_ROUTES, publicRoutes,
        "As rotas públicas documentadas deixaram de corresponder ao contrato esperado do BFF.");
  }

  @Test
  void contratoAsyncApiDescreveEventosRotasCabecalhosEPayloads() throws IOException {
    Path file = contractsDirectory().resolve("eventos.asyncapi.yaml");
    Map<String, Object> document = load(file);
    assertEquals("3.0.0", string(document, "asyncapi"));
    validateLocalReferences(document, document, file.getFileName().toString());

    Map<String, Object> channels = map(document, "channels");
    assertEquals(Set.of("abastecimentoRegistrado", "manutencaoRegistrada"), channels.keySet());
    assertEquals("operacoes.abastecimento.registrado.v1",
        string(castMap(channels.get("abastecimentoRegistrado"), "canal abastecimento"), "address"));
    assertEquals("operacoes.manutencao.registrada.v1",
        string(castMap(channels.get("manutencaoRegistrada"), "canal manutenção"), "address"));

    Map<String, Object> operations = map(document, "operations");
    assertEquals(2, operations.size());
    operations.forEach((name, value) ->
        assertEquals("send", string(castMap(value, "operação " + name), "action")));

    Map<String, Object> schemas = map(map(document, "components"), "schemas");
    assertRequired(schemas, "CabecalhosEvento", "X-Correlation-ID", "eventoId", "eventoVersao");
    assertRequired(schemas, "AbastecimentoRegistrado", "eventoId", "abastecimentoId",
        "veiculoId", "motoristaId", "correlationId");
    assertRequired(schemas, "ManutencaoRegistrada", "eventoId", "manutencaoId",
        "veiculoId", "correlationId");
  }

  private void validateResponses(
      Map<String, Object> operation, String label, String method, String path) {
    Map<String, Object> responses = map(operation, "responses");
    List<String> successes = responses.keySet().stream().filter(code -> code.startsWith("2")).toList();
    assertFalse(successes.isEmpty(), label + " " + method + " " + path + " sem resposta 2xx");
    for (String code : successes) {
      if (code.equals("204")) continue;
      Map<String, Object> response = castMap(responses.get(code), label + " resposta " + code);
      Map<String, Object> content = map(response, "content");
      Map<String, Object> json = map(content, "application/json");
      assertNotNull(json.get("schema"), label + " resposta " + code + " sem schema JSON");
    }
  }

  private void validatePathParameters(
      Map<String, Object> pathItem,
      Map<String, Object> operation,
      String path,
      String label,
      String method) {
    List<Object> parameters = new ArrayList<>();
    parameters.addAll(list(pathItem.get("parameters")));
    parameters.addAll(list(operation.get("parameters")));
    Matcher matcher = PATH_PARAMETER.matcher(path);
    while (matcher.find()) {
      String expected = matcher.group(1);
      boolean declared = parameters.stream()
          .map(value -> castMap(value, label + " parâmetro"))
          .anyMatch(parameter -> expected.equals(parameter.get("name"))
              && "path".equals(parameter.get("in"))
              && Boolean.TRUE.equals(parameter.get("required")));
      assertTrue(declared, label + " " + method + " " + path
          + " não declara o parâmetro obrigatório " + expected);
    }
  }

  private void validateSecurity(
      Map<String, Object> document,
      Map<String, Object> operation,
      String path,
      String label,
      String method) {
    String route = method.toUpperCase(Locale.ROOT) + " " + path;
    Set<String> anonymous = Set.of(
        "GET /api/v1/ambiente",
        "POST /api/v1/auth/login",
        "GET /.well-known/jwks.json",
        "POST /api/v1/identidade/login");
    if (anonymous.contains(route)) return;
    Object security = operation.containsKey("security") ? operation.get("security") : document.get("security");
    assertFalse(list(security).isEmpty(), label + " " + route + " deveria exigir bearerAuth");
  }

  private void validateLocalReferences(Object node, Map<String, Object> root, String label) {
    if (node instanceof Map<?, ?> values) {
      Object reference = values.get("$ref");
      if (reference instanceof String ref && ref.startsWith("#/")) {
        assertNotNull(resolve(root, ref), label + " contém referência inexistente: " + ref);
      }
      values.values().forEach(value -> validateLocalReferences(value, root, label));
    } else if (node instanceof List<?> values) {
      values.forEach(value -> validateLocalReferences(value, root, label));
    }
  }

  private Object resolve(Map<String, Object> root, String reference) {
    Object current = root;
    for (String token : reference.substring(2).split("/")) {
      if (!(current instanceof Map<?, ?> values)) return null;
      current = values.get(token.replace("~1", "/").replace("~0", "~"));
      if (current == null) return null;
    }
    return current;
  }

  private void assertRequired(
      Map<String, Object> schemas, String schemaName, String... expectedProperties) {
    Map<String, Object> schema = castMap(schemas.get(schemaName), "schema " + schemaName);
    Set<String> required = new HashSet<>(list(schema.get("required")).stream()
        .map(String::valueOf).toList());
    assertTrue(required.containsAll(List.of(expectedProperties)),
        schemaName + " não exige todos os campos de correlação e identidade.");
  }

  private String serverPrefix(Map<String, Object> document) {
    List<Object> servers = list(document.get("servers"));
    if (servers.isEmpty()) return "";
    String url = string(castMap(servers.getFirst(), "server"), "url");
    try {
      String path = URI.create(url).getPath();
      return path == null || path.equals("/") ? "" : path.replaceAll("/$", "");
    } catch (IllegalArgumentException ignored) {
      return "";
    }
  }

  private String resolvedPath(String prefix, String path) {
    return prefix.isBlank() || path.startsWith(prefix + "/") ? path : prefix + path;
  }

  private Path contractsDirectory() {
    Path path = Path.of(System.getProperty("user.dir")).toAbsolutePath().getParent().resolve("contracts");
    assertTrue(Files.isDirectory(path), "Pasta contracts não encontrada em " + path);
    return path;
  }

  @SuppressWarnings("unchecked")
  private Map<String, Object> load(Path file) throws IOException {
    LoaderOptions options = new LoaderOptions();
    options.setAllowDuplicateKeys(false);
    options.setMaxAliasesForCollections(50);
    try (InputStream input = Files.newInputStream(file)) {
      Object result = new Yaml(options).load(input);
      return castMap(result, file.getFileName().toString());
    }
  }

  @SuppressWarnings("unchecked")
  private Map<String, Object> castMap(Object value, String label) {
    assertInstanceOf(Map.class, value, label + " deveria ser um objeto YAML");
    return (Map<String, Object>) value;
  }

  private Map<String, Object> map(Map<String, Object> source, String key) {
    return castMap(source.get(key), key);
  }

  private String string(Map<String, Object> source, String key) {
    Object value = source.get(key);
    assertInstanceOf(String.class, value, key + " deveria ser texto");
    return (String) value;
  }

  @SuppressWarnings("unchecked")
  private List<Object> list(Object value) {
    if (value == null) return List.of();
    assertInstanceOf(List.class, value, "Valor deveria ser uma lista YAML");
    return (List<Object>) value;
  }
}
