import AgentsCore
import AgentsManifest
import Foundation
import Testing

struct ManifestExecutableTests {
  @Test(arguments: ["project", "user"])
  func dumpPrintsProducerBytesAndSymbolicValues(_ scope: String) throws {
    let fixture = try CLIFixture()
    let source = """
      version: 1
      # Keep conditions, external references and runtime values symbolic.
      defaultAgents: [opencode, codex]
      sources:
        remote:
          url: https://example.invalid/never-fetch.git
      components:
        - kind: mcpServer
          name: workspace
          transport:
            kind: stdio
            executable: never-run
            environment:
              TOKEN: {secret: token}
          condition: {scopes: [user], platforms: [linux]}
        - kind: command
          name: review
          description: Review
          prompt: {file: {path: missing-prompt.md}}
        - kind: lspServer
          name: swift
          run: {executable: never-run}
          languages: {.swift: swift}
          initializationOptions:
            whole: 1
            precise: !!float "1.00"
        - kind: instructions
          chatgpt:
            weekly:
              sections: [{name: own}]
      uses: [{group: external, source: remote}]
      """
    try fixture.writeManifest(source, scope: scope)
    // The other scope must not influence selection.
    try fixture.writeManifest("invalid other scope", scope: scope == "user" ? "project" : "user")
    let url = fixture.state("agents.yaml", scope: scope)
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
        "schemaVersion", "kind", "format", "manifestVersion", "sourceDigest", "declaration",
        "locations",
        "diagnostics",
      ])
    #expect(dump["schemaVersion"] as? Int == 2 && dump["kind"] as? String == "manifest")
    #expect(dump["format"] as? String == "yaml" && dump["manifestVersion"] as? Int == 1)
    let declaration = try #require(dump["declaration"] as? [String: Any])
    #expect(declaration["defaultAgents"] as? [String] == ["opencode", "codex"])
    #expect((declaration["uses"] as? [[String: Any]])?.first?["source"] as? String == "remote")
    #expect(
      result.stdout.contains("\"kind\": \"secret\"") && result.stdout.contains("missing-prompt.md"))
    let locations = try #require(dump["locations"] as? [[String: Any]])
    #expect(!locations.isEmpty)
    #expect(
      locations.contains {
        ($0["pointer"] as? String)?.hasPrefix("/components/3/chatGPT/0") == true
      })
    let components = try #require(declaration["components"] as? [[String: Any]])
    let options = try #require(components[2]["initializationOptions"] as? [String: [String: Any]])
    #expect(options["whole"]?["kind"] as? String == "integer")
    #expect(options["whole"]?["value"] as? Int == 1)
    #expect(options["precise"]?["kind"] as? String == "decimal")
    #expect(options["precise"]?["value"] as? String == "1.00")
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
    ("{}", "manifest.schema"),
    ("version: 2", "manifest.schema"),
    ("version: 1\nunknown: []", "manifest.schema"),
    ("version: 1\ncomponents: [", "manifest.syntax"),
    ("version: 1\ncomponents: {}", "manifest.schema"),
  ])
  func malformedManifestHasLocatedDiagnostics(source: String, code: String) throws {
    let fixture = try CLIFixture()
    try fixture.writeManifest(source)
    let before = try Data(contentsOf: fixture.state("agents.yaml"))
    let result = try fixture.run(["manifest", "dump", "--json"])
    #expect(result.status == 1 && result.stdout.isEmpty)
    #expect(result.stderr.contains("agents.yaml:") && result.stderr.contains("[\(code)]"))
    #expect(result.stderr.hasSuffix("\n  Fix the reported agents.yaml diagnostics and retry.\n"))
    #expect(!result.stderr.contains("ManifestFailure(") && !result.stderr.contains("metrics:"))
    #expect(try Data(contentsOf: fixture.state("agents.yaml")) == before)
    #expect(
      try FileManager.default.contentsOfDirectory(atPath: fixture.state("").path) == [
        "agents.yaml"
      ])
  }

  @Test(arguments: ["project", "user"])
  func missingManifestDoesNotCreateState(_ scope: String) throws {
    let fixture = try CLIFixture()
    let result = try fixture.run(["manifest", "dump", "--json", "--scope", scope])
    #expect(result.status == 1 && result.stdout.isEmpty)
    #expect(
      result.stderr.contains("Not found: declaration at")
        && result.stderr.contains("Create agents.yaml"))
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
    try FileManager.default.removeItem(at: fixture.state("agents.yaml", scope: scope))
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
          && result.stderr.contains("Restore agents.yaml"))
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
        try FileManager.default.removeItem(at: fixture.state("agents.yaml", scope: scope))
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
          !result.stderr.contains("[manifest.")
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
      version: 1

      # Team-owned defaults. Keep this spelling and spacing.
      defaultAgents: [codex]

      """
    let manifest =
      prefix + """
        sources:
          # Local collection, shared by skills and instructions.
          rules:
            path: \(fixture.source.path.debugDescription)
        components: [] # Deployment list.
        watch: [] # Observations.
        # Keep the footer.
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
        contentsOf: fixture.state("agents.yaml", scope: scope), encoding: .utf8)
      #expect(text.hasPrefix(prefix))
      #expect(text.contains("# Local collection, shared by skills and instructions."))
      #expect(
        text.contains("# Deployment list.") && text.contains("# Observations.")
          && text.hasSuffix("# Keep the footer.\n"))
    }
    let files = ["agents.yaml", "agents.resolved", "agents.watch"].map {
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
        contentsOf: fixture.state("agents.yaml", scope: scope), encoding: .utf8)
      #expect(text.hasPrefix(prefix) && text.hasSuffix("# Keep the footer.\n"))
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
      try String(contentsOf: fixture.state("agents.yaml", scope: scope), encoding: .utf8)
        == "invalid manifest\n")
  }
}
