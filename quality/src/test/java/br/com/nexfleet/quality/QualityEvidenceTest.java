package br.com.nexfleet.quality;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

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
  void diagramasRepresentamAsTabelasMigradasEFluxoCritico() throws IOException {
    Path root = projectRoot();
    Path diagrams = root.resolve("docs").resolve("DIAGRAMAS-ARQUITETURA.md");
    assertTrue(Files.isRegularFile(diagrams), "Diagramas de arquitetura não encontrados.");
    String content = Files.readString(diagrams, StandardCharsets.UTF_8);

    for (String section : List.of(
        "C4 — nível 1", "C4 — nível 2", "C4 — nível 3", "C4 — nível 4",
        "UML de componentes", "UML de sequência", "DER físico")) {
      assertTrue(content.contains(section), "Seção arquitetural ausente: " + section);
    }

    Set<String> migratedTables = new TreeSet<>();
    for (Path migrationRoot : List.of(
        root.resolve("services"), root.resolve("functions").resolve("notificar-abastecimento"))) {
      if (!Files.isDirectory(migrationRoot)) continue;
      try (var paths = Files.walk(migrationRoot)) {
        paths.filter(path -> path.toString().replace('\\', '/').contains(
                "/src/main/resources/db/migration/"))
            .filter(path -> path.toString().endsWith(".sql"))
            .forEach(path -> migratedTables.addAll(readCreatedTables(path)));
      }
    }
    assertEquals(11, migratedTables.size(), "Inventário inesperado de tabelas de negócio.");
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
      assertTrue(javaSourceExists(root, className), "Fonte Java não encontrado: " + className);
    }
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

  private static boolean javaSourceExists(Path root, String className) throws IOException {
    try (var paths = Files.walk(root.resolve("services"))) {
      if (paths.anyMatch(path -> path.getFileName().toString().equals(className + ".java"))) {
        return true;
      }
    }
    try (var paths = Files.walk(root.resolve("functions"))) {
      return paths.anyMatch(path -> path.getFileName().toString().equals(className + ".java"));
    }
  }
}
