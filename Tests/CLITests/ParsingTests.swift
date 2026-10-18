import AgentsCore
import ArgumentParser
import Testing

@testable import CLI

struct ParsingTests {
  @Test func addOptions() throws {
    let command = try #require(
      try Agents.parseAsRoot([
        "skills", "add", "owner/repo", "one", "two", "--agent", "codex", "--agent", "claude",
        "--scope", "user", "--path", "collection", "--full-depth", "--mode", "copy", "--branch",
        "main",
      ]) as? Add)
    #expect(command.source == "owner/repo")
    #expect(command.names == ["one", "two"])
    #expect(command.agents.recipients == [.claudeCode, .codex])
    #expect(command.location.scope == .user)
    #expect(command.discovery.path == "collection" && command.discovery.fullDepth)
    #expect(command.mode == .copy && !command.all)
    #expect(command.requirements.requirement == .branch("main"))
    let all = try #require(try Agents.parseAsRoot(["skills", "add", ".", "--all"]) as? Add)
    #expect(all.all && all.names.isEmpty)
    #expect(all.location.scope == .project && all.mode == .link)
    #expect(all.agents.recipients == nil && all.requirements.requirement == nil)
  }

  @Test(arguments: [
    (["--branch", "main"], SourceRequirement.branch("main")),
    (["--revision", "abc123"], .revision("abc123")),
    (["--exact", "1.2.3"], .exact("1.2.3")),
    (["--from", "1.2.3"], .upToNextMajor(from: "1.2.3")),
    (["--up-to-next-minor-from", "1.2.3"], .upToNextMinor(from: "1.2.3")),
    (["--from", "1.2.3", "--to", "2.0.0"], .range(from: "1.2.3", to: "2.0.0")),
  ])
  func requirements(arguments: [String], expected: SourceRequirement) throws {
    let command = try #require(
      try Agents.parseAsRoot(["skills", "add", "owner/repo"] + arguments) as? Add)
    #expect(command.requirements.requirement == expected)
  }

  @Test(arguments: ["link", "copy", "edit"])
  func modes(_ mode: String) throws {
    let command = try #require(
      try Agents.parseAsRoot(["skills", "add", ".", "--mode", mode]) as? Add)
    #expect(command.mode.rawValue == mode)
  }

  @Test func listOptions() throws {
    let source = try #require(
      try Agents.parseAsRoot([
        "skills", "list", "team", "--path", "skills", "--full-depth", "--json", "--scope", "user",
        "--agent", "gemini",
      ]) as? ListSkills)
    #expect(source.source == "team" && source.discovery.path == "skills")
    #expect(source.discovery.fullDepth && source.json && source.location.scope == .user)
    #expect(source.agents.recipients == [.geminiCLI])
    let installed = try #require(try Agents.parseAsRoot(["skills", "list"]) as? ListSkills)
    #expect(installed.source == nil && installed.agents.recipients == nil)
  }

  @Test func removeOptions() throws {
    let command = try #require(
      try Agents.parseAsRoot([
        "skills", "remove", "one", "two", "--scope", "user", "--agent", "cursor", "--agent",
        "opencode",
      ]) as? Remove)
    #expect(command.names == ["one", "two"] && command.location.scope == .user)
    #expect(command.agents.recipients == [.cursor, .opencode])
    let all = try #require(try Agents.parseAsRoot(["skills", "remove", "one"]) as? Remove)
    #expect(all.agents.recipients == nil)
  }

  @Test func lifecycleOptions() throws {
    let install = try #require(try Agents.parseAsRoot(["install", "--scope", "user"]) as? Install)
    #expect(install.location.scope == .user)
    let update = try #require(
      try Agents.parseAsRoot(["update", "--scope", "user", "--apply"]) as? Update)
    #expect(update.options.apply && !update.options.json && update.options.location.scope == .user)
    let preview = try #require(try Agents.parseAsRoot(["update", "--json"]) as? Update)
    #expect(preview.options.json && !preview.options.apply)
    let named = try #require(
      try Agents.parseAsRoot(["skills", "update", "one", "two", "--json", "--scope", "user"])
        as? UpdateSkills)
    #expect(named.names == ["one", "two"] && named.options.json)
    #expect(named.options.location.scope == .user)
    let apply = try #require(
      try Agents.parseAsRoot(["skills", "update", "--apply"]) as? UpdateSkills)
    #expect(apply.options.apply && apply.names.isEmpty)
  }

  @Test func doctorOptions() throws {
    let doctor = try #require(
      try Agents.parseAsRoot([
        "doctor", "--root", "first", "second", "--root", "third", "--agent", "codex", "--json",
      ]) as? Doctor)
    #expect(doctor.root == ["first", "second", "third"])
    #expect(doctor.json && doctor.agents.recipients == [.codex])
    let user = try #require(try Agents.parseAsRoot(["doctor", "--scope", "user"]) as? Doctor)
    #expect(user.root.isEmpty && user.location.scope == .user)
  }

  @Test func initializeArguments() throws {
    let current = try #require(try Agents.parseAsRoot(["skills", "init"]) as? Initialize)
    #expect(current.name == nil)
    let named = try #require(try Agents.parseAsRoot(["skills", "init", "demo"]) as? Initialize)
    #expect(named.name == "demo")
  }

  @Test(arguments: [
    ["unknown"], ["skills", "unknown"], ["skills", "add"], ["skills", "remove"],
    ["skills", "add", ".", "name", "--all"], ["skills", "add", ".", "--mode", "unknown"],
    ["skills", "add", ".", "--branch", "main", "--revision", "123"],
    ["skills", "add", ".", "--exact", "1.0.0", "--from", "1.0.0"],
    ["skills", "add", ".", "--to", "2.0.0"], ["skills", "add", ".", "--exact", "invalid"],
    ["skills", "add", ".", "--from", "2.0.0", "--to", "1.0.0"],
    ["skills", "add", ".", "--mode", "edit", "--branch", "main"],
    ["skills", "list", "--scope", "global"], ["skills", "list", "--agent", "unknown"],
    ["skills", "list", "--path", "skills"], ["skills", "list", "--full-depth"],
    ["install", "--agent", "codex"], ["install", "--mode", "copy"], ["install", "source"],
    ["update", "name"], ["update", "--apply", "--json"],
    ["skills", "update", "--apply", "--json"], ["doctor", "--scope", "user", "--root", "."],
    ["skills", "add", ".", "--json"], ["skills", "init", "one", "two"],
  ])
  func invalidArguments(_ arguments: [String]) {
    #expect(throws: (any Error).self) { try Agents.parseAsRoot(arguments) }
  }
}
