import AgentsCore
import ArgumentParser
import Foundation
import Testing

@testable import CLI

struct ComponentExecutableTests {
  private func command(_ name: String = "review", body: String = "Review sources.") -> String {
    """
    - kind: command
      name: \(name)
      description: Review
      prompt: \(body.debugDescription)
      agents: [claude-code]
    """
  }

  @Test(arguments: ["project", "user"])
  func componentOnlyUpdateRestoreAndDoctor(_ scope: String) throws {
    let fixture = try CLIFixture()
    let args = ["--scope", scope]
    try fixture.writeManifest(
      "version: 1\n# Preserve this comment\ncomponents:\n" + command(), scope: scope)
    let authored = try Data(contentsOf: fixture.state("agents.yaml", scope: scope))
    let preview = try fixture.success(["update", "--json"] + args).json()
    let changes = try #require(preview["components"] as? [[String: Any]])
    #expect(
      changes.contains { $0["kind"] as? String == "command" && $0["name"] as? String == "review" })
    #expect(preview["schemaVersion"] as? Int == 2 && preview["changed"] as? Bool == true)
    #expect(try Data(contentsOf: fixture.state("agents.yaml", scope: scope)) == authored)
    try fixture.success(["update", "--apply"] + args)
    let listed = try fixture.success(["components", "list", "--json"] + args).json()
    #expect((listed["components"] as? [[String: Any]])?.count == 1)
    let diagnosis = try fixture.run(["doctor", "--json"] + args)
    #expect(diagnosis.status == 0 && diagnosis.stderr.isEmpty)
    let doctor = try diagnosis.json()
    let roots = try #require(doctor["roots"] as? [[String: Any]])
    let checks = try #require(roots.first?["checks"] as? [[String: Any]])
    let target = try #require(
      checks.first { $0["kind"] as? String == "components" }?["path"] as? String)
    try FileManager.default.removeItem(atPath: target)
    let broken = try fixture.run(["doctor", "--json"] + args)
    #expect(broken.status == 1)
    #expect(!FileManager.default.fileExists(atPath: target))
    let restored = try fixture.success(["install", "--json"] + args).json()
    #expect(restored["schemaVersion"] as? Int == 2)
    #expect((restored["components"] as? [[String: Any]])?.isEmpty == false)
    #expect(FileManager.default.fileExists(atPath: target))
    #expect(try Data(contentsOf: fixture.state("agents.yaml", scope: scope)) == authored)
    let noOp = try fixture.success(["update", "--json"] + args).json()
    #expect(noOp["changed"] as? Bool == false)
    try fixture.success(["components", "remove", "review"] + args)
    #expect(
      try String(contentsOf: fixture.state("agents.yaml", scope: scope), encoding: .utf8).contains(
        "# Preserve this comment"))
  }

  @Test func discoveryIsReadOnlyAndAddUsesCoreGroupIntent() throws {
    let fixture = try CLIFixture()
    try FileManager.default.createDirectory(
      at: fixture.source.appendingPathComponent(".agent"), withIntermediateDirectories: true)
    let producer =
      "version: 1\ngroups:\n  tools:\n    components:\n"
      + command().split(separator: "\n").map { "      " + $0 }.joined(separator: "\n")
      + "\nexports: [tools]\n"
    try Data(producer.utf8).write(to: fixture.source.appendingPathComponent(".agent/agents.yaml"))
    let selection = [fixture.source.path, "--alias", "tools", "--group", "tools"]
    let listed = try fixture.success(["components", "list"] + selection + ["--json"]).json()
    #expect((listed["components"] as? [[String: Any]])?.first?["name"] as? String == "review")
    #expect(!FileManager.default.fileExists(atPath: fixture.state("agents.yaml").path))
    try fixture.success(["components", "add"] + selection)
    #expect(try fixture.declaration().uses.contains { $0.name == "tools" && $0.source == "tools" })
    let before = try Data(contentsOf: fixture.state("agents.yaml"))
    let refused = try fixture.run(["components", "remove", "review"])
    #expect(refused.status == 1 && refused.stderr.contains("notEditableHere"))
    #expect(try Data(contentsOf: fixture.state("agents.yaml")) == before)
  }

  @Test func missingAndPendingInspectionDoesNotCreateOrRecoverState() throws {
    let fixture = try CLIFixture()
    try fixture.success(["components", "list", "--json"])
    #expect(!FileManager.default.fileExists(atPath: fixture.state("").path))
    try fixture.writeManifest("version: 1")
    let pending = fixture.state("transaction.new")
    try Data("pending".utf8).write(to: pending)
    let before = try Data(contentsOf: pending)
    for command in [["components", "list"], ["mcp", "test", "server"]] {
      let result = try fixture.run(command)
      #expect(result.status == 1 && result.stdout.isEmpty)
      #expect(try Data(contentsOf: pending) == before)
    }
  }

  @Test func exactSelectionRefusesDuplicateNamesAndUsesIdentity() throws {
    let fixture = try CLIFixture()
    try fixture.writeManifest(
      """
      version: 1
      components:
        - kind: command
          name: same
          description: Command
          prompt: Review
          agents: [claude-code]
        - kind: subagent
          name: same
          description: Agent
          prompt: Research
          agents: [codex]
      """)
    try fixture.success(["update", "--apply"])
    let before = try Data(contentsOf: fixture.state("agents.yaml"))
    let ambiguous = try fixture.run(["components", "remove", "same"])
    #expect(ambiguous.status == 1 && ambiguous.stderr.contains("ambiguous"))
    #expect(try Data(contentsOf: fixture.state("agents.yaml")) == before)
    let report = try fixture.success(["components", "list", "--json"]).json()
    let items = try #require(report["components"] as? [[String: Any]])
    let selected = try #require(items.first { $0["kind"] as? String == "command" })
    let identity = try #require(selected["identity"] as? String)
    let occurrences = try #require(selected["occurrences"] as? [[String: Any]])
    let occurrence = try #require(occurrences.first?["id"] as? Int)
    try fixture.success([
      "components", "remove", "same", "--identity", identity, "--occurrence", String(occurrence),
    ])
    #expect(try fixture.declaration().components.contains { $0.kind == .subagent })
  }

  @Test func importPreviewIsReadOnlyAndApplyKeepsAuthoredComments() throws {
    let fixture = try CLIFixture()
    try fixture.writeManifest("version: 1\n# Authored intent")
    let input = fixture.source.appendingPathComponent("review.md")
    try Data("---\ndescription: Review changes\n---\nReview exact changes.\n".utf8).write(to: input)
    let args = [
      "import", "review.md", "--root", fixture.source.path, "--format", "claudeCommandV1",
    ]
    let authored = try Data(contentsOf: fixture.state("agents.yaml"))
    let preview = try fixture.success(args + ["--json"]).json()
    #expect(preview["kind"] as? String == "import")
    #expect((preview["components"] as? [[String: Any]])?.count == 1)
    #expect(try Data(contentsOf: fixture.state("agents.yaml")) == authored)
    try Data("---\ndescription: Review changes\n---\nReview newly saved changes.\n".utf8).write(
      to: input)
    try fixture.success(args + ["--apply"])
    #expect(
      try String(contentsOf: fixture.state("agents.yaml"), encoding: .utf8).contains(
        "# Authored intent"))
    let diagnosis = try fixture.run(["doctor", "--json"])
    #expect(diagnosis.status == 0 && diagnosis.stderr.isEmpty)
    let roots = try #require(try diagnosis.json()["roots"] as? [[String: Any]])
    let checks = try #require(roots.first?["checks"] as? [[String: Any]])
    let target = try #require(
      checks.first { $0["kind"] as? String == "components" }?["path"] as? String)
    #expect(
      try String(contentsOfFile: target, encoding: .utf8).contains("Review newly saved changes."))
  }

  @Test func runtimePreviewDoesNotRequestBindingsAndMCPRequiresExplicitMapping() throws {
    let fixture = try CLIFixture()
    let authored = """
      version: 1
      components:
        - kind: mcpServer
          name: selected
          agents: []
          transport:
            kind: stdio
            executable: never-start-without-a-binding
            environment: {TOKEN: {secret: selected-token}}
      """
    try fixture.writeManifest(
      authored.replacingOccurrences(of: "agents: []", with: "agents: [codex]"))
    let preview = try fixture.success([
      "update", "--json", "--binding", "selected-token=MISSING_VALUE",
    ])
    #expect(!preview.stdout.contains("runtime binding unavailable"))
    #expect(preview.stdout.contains("selected-token"))
    try fixture.writeManifest(authored)
    try fixture.success(["update", "--apply"])
    let before = try Data(contentsOf: fixture.state("agents.resolved"))
    let result = try fixture.run(["mcp", "test", "selected"])
    #expect(result.status == 1)
    #expect(result.stderr.contains("runtime binding unavailable: selected-token"))
    #expect(try Data(contentsOf: fixture.state("agents.resolved")) == before)
  }

  @Test func restoreFailureDoesNotPublishPartialSkillSuccess() throws {
    let fixture = try CLIFixture()
    try fixture.skill()
    try fixture.commit()
    try fixture.success([
      "skills", "add", fixture.source.path, "--mode", "copy", "--agent", "codex",
    ])
    try fixture.writeManifest(
      "version: 1\nsources:\n  source: {path: \(fixture.source.path.debugDescription)}\ncomponents:\n- kind: skills\n  source: source\n  select: [demo]\n  mode: copy\n  agents: [codex]\n"
        + command())
    try fixture.success(["update", "--apply"])
    let skills = try fixture.success(["skills", "list", "--json"]).json()
    let rows = try #require(skills["skills"] as? [[String: Any]])
    let path = try #require(rows.first?["path"] as? String)
    let diagnosis = try fixture.run(["doctor", "--json"])
    #expect(diagnosis.status == 0 && diagnosis.stderr.isEmpty)
    let roots = try #require(try diagnosis.json()["roots"] as? [[String: Any]])
    let checks = try #require(roots.first?["checks"] as? [[String: Any]])
    let native = try #require(
      checks.first { $0["kind"] as? String == "components" }?["path"] as? String)
    try FileManager.default.removeItem(atPath: path)
    let commands = URL(fileURLWithPath: native).deletingLastPathComponent()
    try FileManager.default.removeItem(at: commands)
    try Data("retained conflicting parent".utf8).write(to: commands)
    let result = try fixture.run(["install"])
    #expect(result.status == 1 && result.stdout.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: path))
    #expect(try String(contentsOf: commands, encoding: .utf8) == "retained conflicting parent")
  }

  @Test func failedMCPConnectionReportsCleanupWithoutChangingState() throws {
    let fixture = try CLIFixture()
    try fixture.writeManifest(
      """
      version: 1
      components:
        - kind: mcpServer
          name: unavailable
          agents: []
          transport:
            kind: stdio
            executable: agents-owned-missing-fixture
      """)
    try fixture.success(["update", "--apply"])
    let before = try Data(contentsOf: fixture.state("agents.resolved"))
    let result = try fixture.run(["mcp", "test", "unavailable", "--json"])
    #expect(result.status == 1 && result.stderr.isEmpty)
    let report = try result.json()
    #expect(report["kind"] as? String == "mcp-test" && report["schemaVersion"] as? Int == 1)
    #expect(report["outcome"] as? String == "failed")
    #expect(report["cleanupComplete"] as? Bool == true)
    #expect((report["tools"] as? [[String: Any]])?.isEmpty == true)
    #expect(try Data(contentsOf: fixture.state("agents.resolved")) == before)
  }

  @Test func bindingMappingIsExplicitLazyAndBounded() throws {
    let options = try BindingOptions.parse(["--binding", "token=EXPLICIT_VALUE"])
    let provider = try options.provider()
    let runtime = RuntimeEnvironment(environment: [
      "EXPLICIT_VALUE": "private-canary", "OTHER": "unrelated",
    ])
    #expect(try provider.value(for: "token", environment: runtime) == Data("private-canary".utf8))
    #expect(throws: CoreError.invalidState("runtime binding unavailable: other")) {
      try provider.value(for: "other", environment: runtime)
    }
    #expect(throws: (any Error).self) {
      try BindingOptions.parse(["--binding", "token=A", "--binding", "token=B"])
    }
  }
}
