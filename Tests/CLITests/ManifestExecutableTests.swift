import AgentsCore
import AgentsManifest
import Foundation
import Testing

struct ManifestExecutableTests {
  @Test(arguments: ["project", "user"])
  func dumpPrintsProducerBytesAndSymbolicValues(_ scope: String) throws {
    let fixture = try CLIFixture()
    let source = """
      // agents-tools-version: 1.0
      import AgentsDescription
      // Keep conditions, external references and runtime values symbolic.
      let recipients: [Agent] = [.openCode, .codex]
      let agents = Agents(
        defaultAgents: recipients,
        sources: [.source(name: "remote", url: "https://example.invalid/never-fetch.git")],
        components: [
          .mcpServer(
            name: "workspace",
            transport: .stdio("never-run", environment: ["TOKEN": .secret("token")]),
            condition: .when(scopes: [.user], platforms: [.linux])
          ),
          .command(name: "review", description: "Review", prompt: .file("missing-prompt.md")),
        ],
        uses: [.group(name: "external", source: "remote")]
      )
      """
    try fixture.writeManifest(source, scope: scope)
    // The other scope must not influence selection.
    try fixture.writeManifest("invalid other scope", scope: scope == "user" ? "project" : "user")
    let url = fixture.state("Agents.swift", scope: scope)
    let bytes = try Data(contentsOf: url)
    let before = try FileManager.default.subpathsOfDirectory(
      atPath: url.deletingLastPathComponent().path)
    let result = try fixture.success(["manifest", "dump", "--json", "--scope", scope])
    #expect(Data(result.stdout.utf8) == Data(try ManifestDump(bytes: Array(bytes)).encodedJSON()))
    #expect(
      try fixture.success(["manifest", "dump", "--json", "--scope", scope]).stdout == result.stdout)
    let dump = try result.json()
    #expect(
      Set(dump.keys) == [
        "schemaVersion", "kind", "languageVersion", "sourceDigest", "declaration", "locations",
        "diagnostics",
      ])
    #expect(dump["schemaVersion"] as? Int == 1 && dump["kind"] as? String == "manifest")
    #expect(dump["languageVersion"] as? String == "1.0")
    let declaration = try #require(dump["declaration"] as? [String: Any])
    #expect(declaration["defaultAgents"] as? [String] == ["codex", "opencode"])
    #expect((declaration["uses"] as? [[String: Any]])?.first?["source"] as? String == "remote")
    #expect(
      result.stdout.contains("\"kind\": \"secret\"") && result.stdout.contains("missing-prompt.md"))
    let locations = try #require(dump["locations"] as? [[String: Any]])
    #expect(!locations.isEmpty)
    #expect(
      locations.allSatisfy { ($0["span"] as? [String: Any])?["document"] as? String == "manifest" })
    #expect(result.stdout.hasSuffix("\n") && !result.stdout.hasSuffix("\n\n"))
    #expect(
      !result.stdout.contains(fixture.project.path) && !result.stdout.contains(fixture.home.path))
    #expect(try Data(contentsOf: url) == bytes)
    #expect(
      try FileManager.default.subpathsOfDirectory(atPath: url.deletingLastPathComponent().path)
        == before)
  }

  @Test(arguments: [
    ("import AgentsDescription\nlet agents = Agents()", "manifest.version.missing"),
    (
      "// agents-tools-version: 9.0\nimport AgentsDescription\nlet agents = Agents()",
      "manifest.version.unsupported"
    ),
    (
      "// agents-tools-version: 1.0\nimport AgentsDescription\nlet agents = Agents(unknown: [])",
      "manifest.call"
    ),
    (
      "// agents-tools-version: 1.0\nimport AgentsDescription\nlet agents = Agents(components: [",
      "manifest.syntax"
    ),
    (
      "// agents-tools-version: 1.0\nimport AgentsDescription\nprint(\"executed\")\nlet agents = Agents()",
      "manifest.syntax"
    ),
  ])
  func malformedManifestHasLocatedDiagnostics(source: String, code: String) throws {
    let fixture = try CLIFixture()
    try fixture.writeManifest(source)
    let before = try Data(contentsOf: fixture.state("Agents.swift"))
    let result = try fixture.run(["manifest", "dump", "--json"])
    #expect(result.status == 1 && result.stdout.isEmpty)
    #expect(result.stderr.contains("Agents.swift:") && result.stderr.contains("[\(code)]"))
    #expect(result.stderr.hasSuffix("\n  Fix the reported Agents.swift diagnostics and retry.\n"))
    #expect(!result.stderr.contains("ManifestFailure(") && !result.stderr.contains("metrics:"))
    #expect(try Data(contentsOf: fixture.state("Agents.swift")) == before)
    #expect(
      try FileManager.default.contentsOfDirectory(atPath: fixture.state("").path) == [
        "Agents.swift"
      ])
  }

  @Test(arguments: ["project", "user"])
  func missingManifestDoesNotCreateState(_ scope: String) throws {
    let fixture = try CLIFixture()
    let result = try fixture.run(["manifest", "dump", "--json", "--scope", scope])
    #expect(result.status == 1 && result.stdout.isEmpty)
    #expect(
      result.stderr.contains("Not found: declaration at")
        && result.stderr.contains("Create Agents.swift"))
    #expect(!FileManager.default.fileExists(atPath: fixture.state("", scope: scope).path))
  }

  @Test(arguments: [
    ["manifest", "dump"], ["manifest", "dump", "--scope", "global", "--json"],
    ["manifest", "dump", "--json", "--path", "other"], ["manifest", "dump", "other", "--json"],
    ["manifest", "dump", "--json", "--apply"], ["manifest", "unknown", "--help"],
  ])
  func usageErrors(_ arguments: [String]) throws {
    let fixture = try CLIFixture()
    let result = try fixture.run(arguments)
    #expect(result.status == 64 && result.stdout.isEmpty)
    #expect(result.stderr.hasSuffix("\n  Run 'agents --help' for usage.\n"))
    #expect(!FileManager.default.fileExists(atPath: fixture.state("").path))
  }

  @Test(arguments: [[], ["manifest"], ["manifest", "dump"]])
  func help(_ command: [String]) throws {
    let fixture = try CLIFixture()
    let result = try fixture.success(command + ["--help"])
    let option = command.isEmpty ? "manifest" : command == ["manifest"] ? "dump" : "--json"
    #expect(result.stdout.contains(option))
    #expect(!FileManager.default.fileExists(atPath: fixture.state("").path))
  }

  @Test(arguments: ["project", "user"], ["agents.resolved", "agents.watch"])
  func orphanedStateIsReadOnly(scope: String, orphan: String) throws {
    let fixture = try CLIFixture()
    try fixture.skill()
    try fixture.commit()
    if orphan == "agents.watch" {
      try fixture.success(["watch", "add", fixture.source.path, "--scope", scope])
    } else {
      try fixture.success([
        "skills", "add", fixture.source.path, "--agent", "codex", "--scope", scope,
      ])
    }
    try FileManager.default.removeItem(at: fixture.state("Agents.swift", scope: scope))
    let url = fixture.state(orphan, scope: scope)
    let before = try Data(contentsOf: url)
    let paths = try FileManager.default.subpathsOfDirectory(
      atPath: fixture.state("", scope: scope).path
    ).sorted()
    for command in [
      ["manifest", "dump"], ["skills", "list"], ["instructions", "list"], ["watch"], ["update"],
    ] {
      let result = try fixture.run(command + ["--json", "--scope", scope])
      #expect(result.status == 1 && result.stdout.isEmpty)
      #expect(
        result.stderr.contains("Missing declaration at")
          && result.stderr.contains("Restore Agents.swift"))
      #expect(try Data(contentsOf: url) == before)
      #expect(
        try FileManager.default.subpathsOfDirectory(atPath: fixture.state("", scope: scope).path)
          .sorted() == paths)
    }
  }

  @Test(arguments: ["project", "user"])
  func pendingRecoveryPrecedesParsingAndMissingDeclaration(_ scope: String) throws {
    let fixture = try CLIFixture()
    try fixture.writeManifest("invalid manifest", scope: scope)
    let journal = fixture.state("transaction.new", scope: scope)
    try Data("partial journal".utf8).write(to: journal)
    let lock = fixture.state("agents.resolved", scope: scope)
    try Data("incomplete lock".utf8).write(to: lock)
    for missing in [false, true] {
      if missing {
        try FileManager.default.removeItem(at: fixture.state("Agents.swift", scope: scope))
      }
      let paths = try FileManager.default.subpathsOfDirectory(
        atPath: fixture.state("", scope: scope).path
      ).sorted()
      for command in [
        ["manifest", "dump"], ["skills", "list"], ["instructions", "list"], ["watch"], ["update"],
      ] {
        let result = try fixture.run(command + ["--json", "--scope", scope])
        #expect(result.status == 1 && result.stdout.isEmpty)
        #expect(
          result.stderr.contains("Transaction recovery is pending")
            && !result.stderr.contains("Recovered"))
        #expect(
          !result.stderr.contains("manifest.syntax")
            && !result.stderr.contains("Missing declaration"))
        #expect(try Data(contentsOf: journal) == Data("partial journal".utf8))
        #expect(try Data(contentsOf: lock) == Data("incomplete lock".utf8))
        #expect(
          try FileManager.default.subpathsOfDirectory(atPath: fixture.state("", scope: scope).path)
            .sorted() == paths)
      }
    }
  }

  @Test(arguments: ["project", "user"])
  func lifecycleEditsPreserveCommentsAndNoOpBytes(_ scope: String) throws {
    let fixture = try CLIFixture()
    try fixture.skill()
    try fixture.instruction()
    try fixture.commit()
    let prefix = """
      // agents-tools-version: 1.0
      import AgentsDescription

      // Team-owned defaults. Keep this spelling and spacing.
      let team: [Agent] = [.codex]

      """
    let manifest =
      prefix + """
        let agents = Agents(
          defaultAgents: team,
          sources: [
            // Local collection, shared by skills and instructions.
            .source(name: "rules", path: \(fixture.source.path.debugDescription)),
          ],
          components: [], // Deployment list.
          watch: [] // Observations.
        )
        // Keep the footer.
        """
    try fixture.writeManifest(manifest, scope: scope)
    let options = ["--scope", scope]
    for command in [
      ["skills", "add", "rules", "demo"], ["instructions", "add", "rules"],
      ["watch", "add", "rules"],
      ["instructions", "update", "--agent", "codex", "--apply"],
      ["watch", "seen", "rules"], ["watch", "remove", "rules"],
    ] {
      try fixture.success(command + options)
      let text = try String(
        contentsOf: fixture.state("Agents.swift", scope: scope), encoding: .utf8)
      #expect(text.hasPrefix(prefix))
      #expect(text.contains("// Local collection, shared by skills and instructions."))
      #expect(
        text.contains("// Deployment list.") && text.contains("// Observations.")
          && text.hasSuffix("// Keep the footer.\n"))
    }
    let files = ["Agents.swift", "agents.resolved", "agents.watch"].map {
      fixture.state($0, scope: scope)
    }
    let before = try files.map { try Data(contentsOf: $0) }
    for command in [
      ["update", "--apply"], ["install", "--json"], ["instructions", "update", "--apply"],
    ] {
      try fixture.success(command + options)
      #expect(try files.map { try Data(contentsOf: $0) } == before)
    }
    let absent = try fixture.run(["skills", "remove", "absent"] + options)
    #expect(absent.status == 1 && absent.stdout.isEmpty)
    #expect(try files.map { try Data(contentsOf: $0) } == before)
    for command in [
      ["skills", "remove", "demo"], ["instructions", "remove", "canonical-artifacts"],
    ] {
      try fixture.success(command + options)
      let text = try String(
        contentsOf: fixture.state("Agents.swift", scope: scope), encoding: .utf8)
      #expect(text.hasPrefix(prefix) && text.hasSuffix("// Keep the footer.\n"))
    }
  }

  @Test(arguments: ["project", "user"])
  func unresolvedTransactionRequiresOwnerAndPreservesState(_ scope: String) throws {
    let fixture = try CLIFixture()
    try fixture.writeManifest("invalid manifest", scope: scope)
    let journal = fixture.state("transaction.json", scope: scope)
    try Data("{}".utf8).write(to: journal)
    let result = try fixture.run(["doctor", "--json", "--scope", scope])
    #expect(result.status == 1 && result.stderr.isEmpty)
    let roots = try #require(try result.json()["roots"] as? [[String: Any]])
    let checks = try #require(roots.first?["checks"] as? [[String: Any]])
    #expect(
      checks.compactMap { $0["id"] as? String } == [
        "unresolved-transaction", "unresolvedTransaction",
      ])
    #expect(checks.allSatisfy { $0["status"] as? String == "error" })
    #expect(
      checks.allSatisfy { ($0["message"] as? String)?.contains("owner action is required") == true }
    )
    let dump = try fixture.run(["manifest", "dump", "--json", "--scope", scope])
    #expect(dump.status == 1 && dump.stdout.isEmpty)
    #expect(
      dump.stderr.contains("Inspect the retained locations")
        && !dump.stderr.contains("run 'agents install'"))
    #expect(try Data(contentsOf: journal) == Data("{}".utf8))
    #expect(
      try String(contentsOf: fixture.state("Agents.swift", scope: scope), encoding: .utf8)
        == "invalid manifest\n")
  }
}
