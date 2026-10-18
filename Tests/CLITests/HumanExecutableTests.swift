import Foundation
import Testing

@testable import CLI

struct HumanExecutableTests {
  @Test func multilineGitFailureKeepsDiagnosticStructure() throws {
    let fixture = try CLIFixture()
    try fixture.skill()
    try fixture.commit()
    try fixture.success(["skills", "add", fixture.source.path, "demo"])
    try FileManager.default.removeItem(at: fixture.source.appendingPathComponent(".git"))
    let failure = try fixture.run(["skills", "update"])
    #expect(failure.status == 1 && failure.stdout.isEmpty)
    #expect(failure.stderr.hasPrefix("Error: Command failed: /usr/bin/env git "))
    #expect(failure.stderr.contains("\n  fatal: Could not read from remote repository.\n  \n"))
    #expect(
      failure.stderr.hasSuffix(
        "  and the repository exists.\n  Check Git access and the source location.\n"))
    let lines = failure.stderr.split(separator: "\n", omittingEmptySubsequences: false)
    #expect(lines.dropFirst().dropLast().allSatisfy { $0.hasPrefix("  ") })
    #expect(!failure.stderr.contains("\\n") && !failure.stderr.contains("\n  ."))
  }

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
    #expect(!preview.contains("link pdf:") && !preview.contains("cache/"))
    #expect(preview.contains("\(revision.prefix(7)) -> \(newRevision.prefix(7))"))
    #expect(
      preview.contains("AGENTS.md (claude-code, codex)\n--- a/AGENTS.md\n+++ b/AGENTS.md\n@@"))
    #expect(!preview.contains("hash:") && !preview.contains("revision:"))
    let applied = try fixture.success(["update", "--apply"]).stdout
    #expect(applied.components(separatedBy: "Updated pdf for claude-code, codex.\n").count == 2)
    #expect(applied.hasSuffix("Updated AGENTS.md.\n"))
    let removed = try fixture.success(["instructions", "remove", "commits"]).stdout
    #expect(removed.contains("--- a/AGENTS.md\n+++ b/AGENTS.md\n@@"))
    #expect(removed.hasSuffix("Removed commits from AGENTS.md.\n"))
  }

  @Test func topLevelInstructionChangesWithUnchangedSkills() throws {
    let fixture = try CLIFixture()
    let skills = try CLIFixture()
    try skills.skill("pdf")
    try skills.commit()
    let skillSource = skills.root.appendingPathComponent("pdf-skills")
    try FileManager.default.moveItem(at: skills.source, to: skillSource)
    try fixture.success(["skills", "add", skillSource.path, "pdf"])
    try fixture.instruction("code-review", heading: "Code Review", body: "Review code.")
    try fixture.instruction("commits", heading: "Commits", body: "Use clear messages.")
    try fixture.commit()
    try fixture.success([
      "instructions", "add", fixture.source.path, "code-review", "commits",
    ])
    let before = try fixture.git(["rev-parse", "--short=7", "HEAD"]).stdout
      .trimmingCharacters(in: .whitespacesAndNewlines)
    try fixture.instruction("code-review", heading: "Code Review", body: "Review code and tests.")
    try fixture.commit()
    let after = try fixture.git(["rev-parse", "--short=7", "HEAD"]).stdout
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let preview = try fixture.success(["update"]).stdout
    #expect(
      preview.hasPrefix(
        "~ changed  code-review (instructions)  local:\(fixture.source.path)  \(before) -> \(after)\n"
          + "= repinned  commits (instructions)  local:\(fixture.source.path)  \(before) -> \(after)\n"
          + "AGENTS.md (claude-code, codex)\n--- a/AGENTS.md\n+++ b/AGENTS.md\n@@"))
    #expect(preview.contains("-Review code.\n+Review code and tests.\n"))
    #expect(!preview.contains("pdf"))
    #expect(!preview.contains("No skill changes.") && !preview.contains("No instruction changes."))
    let notice = "Preview only. Run again with --apply to write these changes.\n"
    #expect(preview.hasSuffix(notice))
    let applied = try fixture.success(["update", "--apply"]).stdout
    #expect(applied == String(preview.dropLast(notice.count)) + "Updated AGENTS.md.\n")
  }

  @Test func topLevelSkillChanges() throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    try fixture.commit()
    try fixture.success(["skills", "add", fixture.source.path, "pdf"])
    try fixture.skill("pdf", body: "Updated content")
    try fixture.commit()
    for arguments in [["update"], ["update", "--apply"]] {
      let output = try fixture.success(arguments).stdout
      #expect(output.hasPrefix("~ changed  pdf  "))
      #expect(!output.contains("No skill changes.") && !output.contains("No instruction changes."))
      if arguments.contains("--apply") {
        #expect(output.hasSuffix("Updated pdf for claude-code, codex.\n"))
      }
    }
  }

  @Test(arguments: [
    ["update"], ["update", "--apply"],
    ["skills", "update"], ["skills", "update", "--apply"],
    ["instructions", "update"], ["instructions", "update", "--apply"],
  ])
  func unchangedUpdatesReportCommandScope(_ arguments: [String]) throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    try fixture.instruction()
    try fixture.commit()
    try fixture.success(["skills", "add", fixture.source.path, "pdf"])
    try fixture.success(["instructions", "add", fixture.source.path])
    let output = try fixture.success(arguments).stdout
    switch arguments[0] {
    case "skills": #expect(output == "No skill changes.\n")
    case "instructions": #expect(output == "No instruction changes.\n")
    default: #expect(output == "No changes.\n")
    }
  }

  @Test func upstreamControlsAndEmptyFiles() throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf", body: "a\tb\r\nControl: \u{1b}[31m\0")
    try fixture.instruction()
    let removed = fixture.source.appendingPathComponent("skills/pdf/old-empty")
    let added = fixture.source.appendingPathComponent("skills/pdf/new-empty")
    try Data().write(to: removed)
    try fixture.commit()
    try fixture.success(["skills", "add", fixture.source.path, "pdf"])
    try fixture.success(["watch", "add", fixture.source.path])
    try fixture.skill("pdf", body: "a\tc\nControl: \u{1b}[32m\0")
    try FileManager.default.removeItem(at: removed)
    try Data().write(to: added)
    try fixture.commit()
    for arguments in [["skills", "update"], ["watch", "diff", fixture.source.path, "pdf"]] {
      let output = try fixture.success(arguments).stdout
      #expect(output.contains("-a\tb\\r\n"))
      #expect(output.contains("+a\tc\n"))
      #expect(output.contains("-Control: \\x1b[31m\\x00\n"))
      #expect(output.contains("+Control: \\x1b[32m\\x00\n"))
      #expect(output.contains("empty file pdf/new-empty added\n"))
      #expect(output.contains("empty file pdf/old-empty removed\n"))
      #expect(!output.contains("+++ b/pdf/new-empty") && !output.contains("--- a/pdf/old-empty"))
      #expect(!output.contains("\u{1b}") && !output.contains("\r") && !output.contains("\0"))
    }
    try fixture.success(["instructions", "add", fixture.source.path])
    try fixture.declarePrompt()
    try Data("Prompt\tcontent\r\n\u{1b}[31m\0\n".utf8).write(
      to: fixture.project.appendingPathComponent("prompt-custom.md"))
    try fixture.success(["instructions", "update", "--apply"])
    let prompt = try fixture.success(["instructions", "render", "chatgpt", "weekly"]).stdout
    #expect(prompt.contains("Prompt\tcontent\\r\n\\x1b[31m\\x00\n"))
    let error = try fixture.run(["--unknown\u{1b}[31m"])
    #expect(error.stderr.contains("\\x1b[31m") && !error.stderr.contains("\u{1b}"))
    let missing = try fixture.run(["instructions", "add", fixture.source.path, "missing\r\n\t"])
    #expect(missing.status == 1)
    #expect(missing.stderr.contains("missing.\\r\n  Check"))
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
        == "Error: No ChatGPT prompt named 'daily' is declared.\n  Declare it under instructions.chatgpt in agents.json and run 'agents instructions update --apply'.\n"
    )
    #expect(!FileManager.default.fileExists(atPath: fixture.state("").path))
    try fixture.instruction()
    try fixture.commit()
    let invalid = try fixture.run(["instructions", "add", fixture.source.path, "--all"])
    #expect(invalid.status == 64 && invalid.stdout.isEmpty)
    #expect(
      invalid.stderr
        == "Error: Unknown option '--all'. Did you mean '--path'?\n  Run 'agents --help' for usage.\n"
    )
    try fixture.success(["instructions", "add", fixture.source.path])
    try fixture.declarePrompt()
    let unlocked = try fixture.run(["instructions", "render", "chatgpt", "weekly"])
    #expect(unlocked.status == 1)
    #expect(
      unlocked.stderr
        == "Error: A ChatGPT prompt must have at least one locked section.\n  Declare the ChatGPT prompt in agents.json and run 'agents instructions update --apply'.\n"
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
