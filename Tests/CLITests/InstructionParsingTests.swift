import AgentsCore
import Testing

@testable import CLI

struct InstructionParsingTests {
  @Test func addOptions() throws {
    let command = try #require(
      try Agents.parseAsRoot([
        "instructions", "add", "owner/repo", "one", "two", "--replace", "--agent", "codex",
        "--agent", "claude", "--scope", "user", "--path", "collection", "--branch", "main",
      ]) as? AddInstructions)
    #expect(command.source == "owner/repo" && command.names == ["one", "two"])
    #expect(command.replace && command.agents.recipients == [.claudeCode, .codex])
    #expect(command.location.scope == .user && command.discovery.path == "collection")
    #expect(command.requirements.requirement == .branch("main"))
    let defaults = try #require(
      try Agents.parseAsRoot(["instructions", "add", "."]) as? AddInstructions)
    #expect(defaults.names.isEmpty && !defaults.replace && defaults.agents.recipients == nil)
    #expect(defaults.location.scope == .project && defaults.discovery.path == nil)
    #expect(defaults.requirements.requirement == nil)
  }

  @Test(arguments: [
    (["--revision", "abc123"], SourceRequirement.revision("abc123")),
    (["--exact", "1.2.3"], .exact("1.2.3")),
    (["--from", "1.2.3"], .upToNextMajor(from: "1.2.3")),
    (["--up-to-next-minor-from", "1.2.3"], .upToNextMinor(from: "1.2.3")),
    (["--from", "1.2.3", "--to", "2.0.0"], .range(from: "1.2.3", to: "2.0.0")),
  ])
  func requirements(arguments: [String], expected: SourceRequirement) throws {
    let command = try #require(
      try Agents.parseAsRoot(["instructions", "add", "."] + arguments) as? AddInstructions)
    #expect(command.requirements.requirement == expected)
  }

  @Test func listOptions() throws {
    let source = try #require(
      try Agents.parseAsRoot([
        "instructions", "list", "rules", "--scope", "user", "--path", "collection", "--json",
      ]) as? ListInstructions)
    #expect(source.source == "rules" && source.location.scope == .user)
    #expect(source.discovery.path == "collection" && source.json)
    let managed = try #require(
      try Agents.parseAsRoot(["instructions", "list"]) as? ListInstructions)
    #expect(managed.source == nil && managed.location.scope == .project && !managed.json)
  }

  @Test func removeAndUpdateOptions() throws {
    let remove = try #require(
      try Agents.parseAsRoot([
        "instructions", "remove", "rules:one", "two", "--scope", "user", "--agent", "gemini",
      ]) as? RemoveInstructions)
    #expect(remove.names == ["rules:one", "two"] && remove.location.scope == .user)
    #expect(remove.agents.recipients == [.geminiCLI])
    let apply = try #require(
      try Agents.parseAsRoot([
        "instructions", "update", "--apply", "--scope", "user", "--agent", "opencode",
        "--agent", "cursor",
      ]) as? UpdateInstructions)
    #expect(apply.options.apply && !apply.options.json && apply.options.location.scope == .user)
    #expect(apply.agents.recipients == [.cursor, .opencode])
    let preview = try #require(
      try Agents.parseAsRoot(["instructions", "update", "--json"]) as? UpdateInstructions)
    #expect(preview.options.json && !preview.options.apply && preview.agents.recipients == nil)
    let defaults = try #require(
      try Agents.parseAsRoot(["instructions", "update"]) as? UpdateInstructions)
    #expect(!defaults.options.apply && !defaults.options.json)
  }

  @Test func renderInitAndInstall() throws {
    let render = try #require(
      try Agents.parseAsRoot([
        "instructions", "render", "chatgpt", "weekly", "--scope", "user",
      ]) as? RenderChatGPT)
    #expect(render.prompt == "weekly" && render.location.scope == .user)
    let initialize = try #require(
      try Agents.parseAsRoot(["instructions", "init", "canonical-artifacts"])
        as? InitializeInstructions)
    #expect(initialize.name == "canonical-artifacts")
    let install = try #require(
      try Agents.parseAsRoot(["install", "--scope", "user", "--json"]) as? Install)
    #expect(install.json && install.location.scope == .user)
  }

  @Test(arguments: [
    ["instructions", "unknown"], ["instructions", "add"], ["instructions", "remove"],
    ["instructions", "init"], ["instructions", "init", "one", "two"],
    ["instructions", "render", "chatgpt"], ["instructions", "render", "unknown", "prompt"],
    ["instructions", "render", "chatgpt", "prompt", "--json"],
    ["instructions", "list", "--path", "collection"], ["instructions", "list", "--agent", "codex"],
    ["instructions", "list", ".", "--full-depth"], ["instructions", "list", "--scope", "global"],
    ["instructions", "add", ".", "--agent", "chatgpt"], ["instructions", "add", ".", "--all"],
    ["instructions", "add", ".", "--mode", "copy"], ["instructions", "add", ".", "--exact", "bad"],
    ["instructions", "add", ".", "--branch", "main", "--revision", "123"],
    ["instructions", "add", ".", "--to", "2.0.0"],
    ["instructions", "update", "name"], ["instructions", "update", "--apply", "--json"],
    ["instructions", "update", "--path", "collection"],
    ["instructions", "remove", "one", "--replace"],
  ])
  func invalidArguments(_ arguments: [String]) {
    #expect(throws: (any Error).self) { try Agents.parseAsRoot(arguments) }
  }
}
