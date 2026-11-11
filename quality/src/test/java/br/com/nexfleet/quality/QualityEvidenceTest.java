package br.com.nexfleet.quality;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assumptions.assumeTrue;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.Set;
import java.util.TreeSet;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import org.junit.jupiter.api.Test;

class QualityEvidenceTest {
  private static final Pattern CQ_ROW = Pattern.compile("(?m)^\\| (CQ\\d{2}) \\|");
  private static final Pattern CREATE_TABLE = Pattern.compile(
      "(?i)CREATE\\s+TABLE\\s+([a-z_]+\\.[a-z_]+)");
  private static final List<String> SIBLINGS = List.of(
      "gateway", "bff", "identidade", "frota", "operacoes", "indicadores", "function");
  /** Frota guarda veículos, motoristas e vínculos no MongoDB: não há migração SQL dela. */
  private static final Set<String> MIGRATED_TABLES = Set.of(
      "identidade.usuario",
      "operacoes.abastecimento", "operacoes.hodometro", "operacoes.manutencao",
      "operacoes.outbox_evento",
      "indicadores.abastecimento_projecao", "indicadores.manutencao_projecao",
      "notificacoes.email_capturado");

  @Test
  void matrizContemCadaCenarioDeQualidadeUmaUnicaVez() throws IOException {
    Path root = projectRoot();
    Path matrix = root.resolve("docs").resolve("MATRIZ-CQ01-CQ12.md");
    assertTrue(Files.isRegularFile(matrix), "Matriz CQ01-CQ12 não encontrada em " + matrix);

    String content = Files.readString(matrix, StandardCharsets.UTF_8);
    Matcher matcher = CQ_ROW.matcher(content);
    int rows = 0;
    while (matcher.find()) {
      rows++;
      String expected = "CQ%02d".formatted(rows);
      assertEquals(expected, matcher.group(1), "A matriz deve manter CQ01-CQ12 em ordem.");
    }
    assertEquals(12, rows, "A matriz deve conter exatamente os doze cenários de qualidade.");
  }

  @Test
  void diagramasContemAsSecoesArquiteturais() throws IOException {
    Path root = projectRoot();
    Path diagrams = root.resolve("docs").resolve("DIAGRAMAS-ARQUITETURA.md");
    assertTrue(Files.isRegularFile(diagrams), "Diagramas de arquitetura não encontrados.");
    String content = Files.readString(diagrams, StandardCharsets.UTF_8);

    for (String section : List.of(
        "C4 — nível 1", "C4 — nível 2", "C4 — nível 3", "C4 — nível 4",
        "UML de componentes", "UML de sequência", "DER físico")) {
      assertTrue(content.contains(section), "Seção arquitetural ausente: " + section);
    }
  }

  @Test
  void diagramasRepresentamAsTabelasMigradasEFluxoCritico() throws IOException {
    Path root = projectRoot();
    String content = Files.readString(
        root.resolve("docs").resolve("DIAGRAMAS-ARQUITETURA.md"), StandardCharsets.UTF_8);

    // As migrações e os fontes Java vivem nos repositórios irmãos; sem eles clonados
    // lado a lado a checagem contra o código não tem o que conferir.
    List<Path> repositories = siblingRepositories(root);
    List<Path> missing = repositories.stream().filter(path -> !Files.isDirectory(path)).toList();
    assumeTrue(missing.isEmpty(),
        "Repositórios irmãos ausentes (defina -Dnexfleet.repos.dir): " + missing);

    Set<String> migratedTables = new TreeSet<>();
    for (Path repository : repositories) {
      Path migrationRoot = repository.resolve("src").resolve("main").resolve("resources")
          .resolve("db").resolve("migration");
      if (!Files.isDirectory(migrationRoot)) continue;
      try (var paths = Files.walk(migrationRoot)) {
        paths.filter(path -> path.toString().endsWith(".sql"))
            .forEach(path -> migratedTables.addAll(readCreatedTables(path)));
      }
    }
    assertEquals(MIGRATED_TABLES, migratedTables, "Inventário inesperado de tabelas de negócio.");
    for (String table : migratedTables) {
      assertTrue(content.contains("`" + table + "`"),
          "Tabela migrada ausente do inventário DER: " + table);
    }

    for (String className : List.of(
        "GatewayConfig", "AbastecimentosWebController", "GerenciarAbastecimentosWeb",
        "HttpAbastecimentos", "AbastecimentosController", "GerenciarAbastecimentos",
        "JdbcAbastecimentos", "HttpReferenciasFrota", "OutboxPublicacaoJob",
        "PublicarEventosPendentes", "RabbitPublicadorEventos", "RabbitAbastecimentoListener",
        "ProjetarAbastecimento", "JdbcProjecoesAbastecimento",
        "NotificarAbastecimentoFunction", "NotificarAbastecimento",
        "JdbcProvedorEmailCapturado")) {
      assertTrue(content.contains(className), "Classe do fluxo crítico ausente: " + className);
      assertTrue(javaSourceExists(repositories, className), "Fonte Java não encontrado: " + className);
    }
  }

  /** Repositórios irmãos em {@code ../nexfleet-<svc>} ou em {@code -Dnexfleet.repos.dir}. */
  private static List<Path> siblingRepositories(Path root) {
    String configured = System.getProperty("nexfleet.repos.dir", "");
    Path base = configured.isBlank() ? root.getParent() : Path.of(configured).toAbsolutePath();
    return SIBLINGS.stream().map(name -> base.resolve("nexfleet-" + name)).toList();
  }

  private static Path projectRoot() {
    return Path.of(System.getProperty("user.dir")).toAbsolutePath().getParent();
  }

  private static List<String> readCreatedTables(Path path) {
    try {
      Matcher matcher = CREATE_TABLE.matcher(Files.readString(path, StandardCharsets.UTF_8));
      List<String> tables = new ArrayList<>();
      while (matcher.find()) tables.add(matcher.group(1).toLowerCase());
      return tables;
    } catch (IOException error) {
      throw new IllegalStateException("Falha ao ler migração " + path, error);
    }
  }

  private static boolean javaSourceExists(List<Path> repositories, String className)
      throws IOException {
    for (Path repository : repositories) {
      Path sources = repository.resolve("src").resolve("main").resolve("java");
      if (!Files.isDirectory(sources)) continue;
      try (var paths = Files.walk(sources)) {
        if (paths.anyMatch(path -> path.getFileName().toString().equals(className + ".java"))) {
          return true;
        }
      }
    }
    return false;
  }
}
