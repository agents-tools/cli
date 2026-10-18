import Foundation
import Testing

@testable import CLI

struct HumanExecutableTests {
  @Test func completionsAndRepinnedSections() throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    try fixture.instruction("code-review", heading: "Code Review", body: "Review code.")
    try fixture.instruction("commits", heading: "Commits", body: "Use clear messages.")
    try fixture.commit()
    let skill = try fixture.success(["skills", "add", fixture.source.path, "pdf"])
    #expect(skill.stdout == "Installed pdf for claude-code, codex (link).\n")
    let added = try fixture.success([
      "instructions", "add", fixture.source.path, "code-review", "commits",
    ])
    #expect(added.stdout == "Added code-review, commits to AGENTS.md (claude-code, codex).\n")
    let revision = try fixture.git(["rev-parse", "HEAD"]).stdout.trimmingCharacters(
      in: .whitespacesAndNewlines)
    try fixture.instruction("code-review", heading: "Code Review", body: "Review code and tests.")
    try fixture.commit()
    let newRevision = try fixture.git(["rev-parse", "HEAD"]).stdout.trimmingCharacters(
      in: .whitespacesAndNewlines)
    let preview = try fixture.success(["update"]).stdout
    let changed = try #require(
      preview.range(of: "~ changed  code-review (instructions)")?.lowerBound)
    let repinned = try #require(preview.range(of: "= repinned  commits (instructions)")?.lowerBound)
    #expect(changed < repinned)
    #expect(preview.contains("= repinned  pdf"))
    #expect(preview.contains("\(revision.prefix(7)) -> \(newRevision.prefix(7))"))
    #expect(
      preview.contains("AGENTS.md (claude-code, codex)\n--- a/AGENTS.md\n+++ b/AGENTS.md\n@@"))
    #expect(!preview.contains("hash:") && !preview.contains("revision:"))
    let applied = try fixture.success(["update", "--apply"]).stdout
    #expect(
      applied.hasSuffix(
        "Updated .agents/skills/pdf.\nUpdated .claude/skills/pdf.\nUpdated AGENTS.md.\n"))
    let removed = try fixture.success(["instructions", "remove", "commits"]).stdout
    #expect(removed.contains("--- a/AGENTS.md\n+++ b/AGENTS.md\n@@"))
    #expect(removed.hasSuffix("Removed commits from AGENTS.md.\n"))
  }

  @Test func editRecipientChangeAndClaudeForwarding() throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    try fixture.instruction()
    try fixture.commit()
    try fixture.success([
      "skills", "add", fixture.source.path, "pdf", "--mode", "edit", "--agent", "codex",
    ])
    var declaration = try fixture.declaration()
    var skills = try #require(declaration["skills"] as? [String: [String: Any]])
    let alias = try #require(skills.keys.first)
    skills[alias]?["agents"] = ["cursor"]
    declaration["skills"] = skills
    try JSONSerialization.data(withJSONObject: declaration).write(to: fixture.state("agents.json"))
    let preview = try fixture.success(["skills", "update"]).stdout
    #expect(preview.hasPrefix("~ changed  pdf  "))
    try Data("# Claude Guide\n\nCustom notes.\n".utf8).write(
      to: fixture.project.appendingPathComponent("CLAUDE.md"))
    let added = try fixture.success(["instructions", "add", fixture.source.path]).stdout
    #expect(added == "Added canonical-artifacts to AGENTS.md (claude-code, codex).\n")
  }

  @Test func promptErrorsAndUsagePunctuation() throws {
    let fixture = try CLIFixture()
    let missing = try fixture.run(["instructions", "render", "chatgpt", "daily"])
    #expect(missing.status == 1 && missing.stdout.isEmpty)
    #expect(
      missing.stderr
        == "Error: No ChatGPT prompt named 'daily' is declared. Declare it under instructions.chatgpt in agents.json and run 'agents instructions update --apply'.\n"
    )
    #expect(!FileManager.default.fileExists(atPath: fixture.state("").path))
    try fixture.instruction()
    try fixture.commit()
    let invalid = try fixture.run(["instructions", "add", fixture.source.path, "--all"])
    #expect(invalid.status == 64 && invalid.stdout.isEmpty)
    #expect(
      invalid.stderr
        == "Error: Unknown option '--all'. Did you mean '--path'? Run 'agents --help' for usage.\n")
    try fixture.success(["instructions", "add", fixture.source.path])
    try fixture.declarePrompt()
    let unlocked = try fixture.run(["instructions", "render", "chatgpt", "weekly"])
    #expect(unlocked.status == 1)
    #expect(
      unlocked.stderr
        == "Error: A ChatGPT prompt must have at least one locked section. Declare the ChatGPT prompt in agents.json and run 'agents instructions update --apply'.\n"
    )
    let journal = fixture.state("transaction.new")
    try Data("pending".utf8).write(to: journal)
    let pending = try fixture.run(["instructions", "render", "chatgpt", "weekly"])
    #expect(pending.status == 1 && pending.stdout.isEmpty)
    #expect(try Data(contentsOf: journal) == Data("pending".utf8))
    #expect(!pending.stderr.contains("Recovered"))
  }

  @Test func versionedInstructionsAndHomeSource() throws {
    let fixture = try CLIFixture()
    try fixture.instruction()
    try fixture.commit()
    try fixture.git(["tag", "1.2.0"])
    let source = fixture.home.appendingPathComponent("Developer/rules")
    try FileManager.default.createDirectory(
      at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: fixture.source, to: source)
    try FileManager.default.createDirectory(at: fixture.source, withIntermediateDirectories: true)
    try fixture.success(["instructions", "add", source.path])
    let list = try fixture.success(["instructions", "list"]).stdout
    #expect(list.contains("local:~/Developer/rules  1.2.0 ("))
    try fixture.git(["-C", source.path, "tag", "1.3.0"])
    let preview = try fixture.success(["instructions", "update"]).stdout
    #expect(
      preview.contains(
        "= repinned  canonical-artifacts (instructions)  local:~/Developer/rules  1.2.0 ("))
    #expect(preview.contains(" -> 1.3.0 ("))
    #expect(!preview.contains("--- "))
  }
}
