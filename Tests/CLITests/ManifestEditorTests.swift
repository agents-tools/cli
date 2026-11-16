import AgentsCore
import AgentsManifest
import Foundation
import Testing

@testable import CLI

struct ManifestEditorTests {
  @Test func schemaIsExactAndIndependentOfScopeState() throws {
    let fixture = try CLIFixture()
    for scope in ["project", "user"] {
      try fixture.writeManifest("invalid manifest", scope: scope)
      try Data("pending".utf8).write(to: fixture.state("transaction.new", scope: scope))
    }
    let before = try inventory(fixture.root)
    let result = try fixture.success(["manifest", "schema"])
    #expect(Data(result.stdout.utf8) == Data(try ManifestSchemaResource.encodedJSON()))
    #expect(try inventory(fixture.root) == before)
  }

  @Test(arguments: ["project", "user"])
  func checkIsReadOnlyAndLeavesDumpUnchanged(_ scope: String) throws {
    let fixture = try CLIFixture()
    try fixture.writeManifest(
      """
      version: 1
      # The checker must not fetch sources or evaluate deployment conditions.
      sources:
        remote: {url: https://example.invalid/never-fetch.git}
      components:
        - {kind: command, name: review, description: Review, prompt: {file: {path: missing.md}}}
      uses: [{source: remote, group: external}]
      """, scope: scope)
    let arguments = ["--scope", scope]
    let dump = try fixture.success(["manifest", "dump", "--json"] + arguments).stdout
    let before = try inventory(fixture.root)
    let result = try fixture.success(["manifest", "check"] + arguments)
    #expect(result.stdout.isEmpty)
    #expect(try inventory(fixture.root) == before)
    #expect(try fixture.success(["manifest", "dump", "--json"] + arguments).stdout == dump)
  }

  @Test(arguments: ["project", "user"])
  func warningsAreSuccessfulAndLocated(_ scope: String) throws {
    let fixture = try CLIFixture()
    try fixture.writeManifest(
      "version: 1\nsources:\n  rules: {url: github.com/example/rules}\n", scope: scope)
    let before = try inventory(fixture.root)
    let result = try fixture.run(["manifest", "check", "--scope", scope])
    #expect(result.status == 0 && result.stdout.isEmpty)
    #expect(
      result.stderr.contains(
        "\(fixture.state("agents.yaml", scope: scope).path):3: warning [manifest.domain]:"))
    #expect(result.stderr.contains("(UTF-8 byte column "))
    #expect(!result.stderr.contains("Error:") && !result.stderr.contains("Fix the reported"))
    #expect(try inventory(fixture.root) == before)
  }

  @Test(arguments: ["project", "user"])
  func errorsUseLineCoordinatesWithByteColumnsInMessages(_ scope: String) throws {
    let fixture = try CLIFixture()
    let prefix = "sources: {'🙂e\u{301}': {path: .}, "
    try fixture.writeManifest(
      "\u{FEFF}version: 1\r\n# Saved document\r\n" + prefix
        + #"same: {path: .}, "\u0073ame": {path: .}}"#, scope: scope)
    let before = try inventory(fixture.root)
    let result = try fixture.run(["manifest", "check", "--scope", scope])
    #expect(result.status == 1 && result.stdout.isEmpty)
    #expect(
      result.stderr.hasPrefix(
        "\(fixture.state("agents.yaml", scope: scope).path):3: error [manifest.key.duplicate]:"))
    #expect(result.stderr.hasSuffix("(UTF-8 byte column \(prefix.utf8.count + 1))\n"))
    #expect(!result.stderr.contains("related location") && !result.stderr.contains("Error:"))
    #expect(try inventory(fixture.root) == before)
  }

  @Test(arguments: ["project", "user"])
  func missingPendingAndIOFailuresAreCommandFailures(_ scope: String) throws {
    let fixture = try CLIFixture()
    let arguments = ["manifest", "check", "--scope", scope]
    let missing = try fixture.run(arguments)
    #expect(missing.status == 1 && missing.stdout.isEmpty)
    #expect(
      missing.stderr.contains("Not found: declaration at")
        && missing.stderr.contains("Create agents.yaml"))
    #expect(!missing.stderr.contains("[manifest."))
    #expect(!FileManager.default.fileExists(atPath: fixture.state("", scope: scope).path))
    try fixture.writeManifest("invalid YAML", scope: scope)
    try Data("pending".utf8).write(to: fixture.state("transaction.new", scope: scope))
    let before = try inventory(fixture.root)
    let pending = try fixture.run(arguments)
    #expect(pending.status == 1 && pending.stdout.isEmpty)
    #expect(
      pending.stderr.contains("Transaction recovery is pending")
        && !pending.stderr.contains("[manifest."))
    #expect(try inventory(fixture.root) == before)
    try FileManager.default.removeItem(at: fixture.state("transaction.new", scope: scope))
    try FileManager.default.removeItem(at: fixture.state("agents.yaml", scope: scope))
    try FileManager.default.createDirectory(
      at: fixture.state("agents.yaml", scope: scope), withIntermediateDirectories: true)
    let ioBefore = try inventory(fixture.root)
    let io = try fixture.run(arguments)
    #expect(io.status == 1 && io.stdout.isEmpty && !io.stderr.contains("[manifest."))
    #expect(try inventory(fixture.root) == ioBefore)
  }

  @Test(arguments: ["rules:12 [中文]🙂", "rules\nline", "rules\tname"])
  func specialPathsAndMessagesRemainSingleLine(_ name: String) throws {
    let fixture = try CLIFixture()
    let project = fixture.project.appendingPathComponent(name)
    let state = project.appendingPathComponent(".agent")
    try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
    try Data("version: 1\n\"unknown\\nfield\\u2028\": []\n".utf8).write(
      to: state.appendingPathComponent("agents.yaml"))
    let before = try inventory(fixture.root)
    let result = try fixture.run(["manifest", "check"], directory: project)
    #expect(result.status == 1 && result.stdout.isEmpty)
    #expect(result.stderr.filter { $0 == "\n" }.count == 1)
    #expect(result.stderr.contains("unknown\\nfield\\u{2028}"))
    if name.contains("\n") || name.contains("\t") {
      #expect(result.stderr.hasPrefix("Diagnostic at "))
    } else {
      #expect(
        result.stderr.hasPrefix(
          state.appendingPathComponent("agents.yaml").path + ":2: error [manifest.schema]:"))
    }
    #expect(try inventory(fixture.root) == before)
  }

  @Test(arguments: [
    ["manifest", "schema", "--json"], ["manifest", "schema", "--scope", "project"],
    ["manifest", "schema", "file"], ["manifest", "check", "--json"],
    ["manifest", "check", "--scope", "global"], ["manifest", "check", "file"],
  ])
  func usageFailures(_ arguments: [String]) throws {
    let fixture = try CLIFixture()
    let before = try inventory(fixture.root)
    let result = try fixture.run(arguments)
    #expect(result.status == 64 && result.stdout.isEmpty)
    #expect(result.stderr.contains("Run 'agents --help' for usage."))
    #expect(try inventory(fixture.root) == before)
  }

  @Test func diagnosticLinesSanitizeMessagesAndAvoidFalsePathLinks() {
    let diagnostic = ManifestDiagnostic(
      code: "manifest.domain", message: "bad\r\nvalue\t\u{2028}\u{2029}\u{1B}",
      span: SourceSpan(
        document: DocumentIdentity("/project:a [b]/agents.yaml"), start: 0, end: 1, line: 3,
        column: 9),
      related: [
        SourceSpan(
          document: DocumentIdentity("/other/agents.yaml"), start: 0, end: 1, line: 5, column: 7)
      ])
    #expect(
      ManifestDiagnostics.render(diagnostic)
        == "/project:a [b]/agents.yaml:3: error [manifest.domain]: bad\\r\\nvalue\\t\\u{2028}\\u{2029}\\x1b (UTF-8 byte column 9)\n/other/agents.yaml:5: info [manifest.domain]: related location (UTF-8 byte column 7)\n"
    )
    let unusual = ManifestDiagnostic(
      code: "manifest.schema", message: "invalid",
      span: SourceSpan(
        document: DocumentIdentity("/project\nname/agents.yaml"), start: 0, end: 1, line: 2,
        column: 1))
    #expect(
      ManifestDiagnostics.render(unusual).hasPrefix(
        "Diagnostic at /project\\nname/agents.yaml (line 2): error [manifest.schema]:"))
  }

  private func inventory(_ root: URL) throws -> [String: String] {
    let manager = FileManager.default
    // CLIFixture owns these two root-level output captures; every CLI state path stays included.
    return try Dictionary(
      uniqueKeysWithValues: manager.subpathsOfDirectory(atPath: root.path).filter {
        $0 != "stdout" && $0 != "stderr"
      }.map { path in
        let url = root.appendingPathComponent(path)
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        if values.isSymbolicLink == true {
          return (path, "link:" + (try manager.destinationOfSymbolicLink(atPath: url.path)))
        }
        if values.isDirectory == true { return (path, "directory") }
        return (path, "file:" + (try Data(contentsOf: url)).base64EncodedString())
      })
  }
}
