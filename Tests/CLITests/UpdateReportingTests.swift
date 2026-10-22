import AgentsCore
import AgentsUpdates
import Foundation
import Testing

@testable import CLI

struct UpdateReportingTests {
  @Test(arguments: [["skills", "update"], ["update"]], ["link", "copy"])
  func versionsAndExecutableChanges(command: [String], mode: String) throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    let script = fixture.source.appendingPathComponent("skills/pdf/run.sh")
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: script)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: script.path)
    try fixture.commit()
    try fixture.git(["tag", "1.2.0"])
    let oldRevision = try fixture.git(["rev-parse", "HEAD"]).stdout.trimmingCharacters(
      in: .whitespacesAndNewlines)
    try fixture.success(["skills", "add", fixture.source.path, "pdf", "--mode", mode])
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    try fixture.commit()
    try fixture.git(["tag", "1.3.0"])
    let newRevision = try fixture.git(["rev-parse", "HEAD"]).stdout.trimmingCharacters(
      in: .whitespacesAndNewlines)
    let report = try fixture.success(command + ["--json"]).json()
    #expect(report["schemaVersion"] as? Int == 1)
    let skill = try #require((report["skills"] as? [[String: Any]])?.first)
    #expect(skill["oldVersion"] as? String == "1.2.0")
    #expect(skill["newVersion"] as? String == "1.3.0")
    #expect(skill["oldRevision"] as? String == oldRevision)
    #expect(skill["newRevision"] as? String == newRevision)
    #expect(skill["oldHash"] as? String == skill["newHash"] as? String)
    let files = try #require(skill["files"] as? [[String: Any]])
    let changedScript = try #require(
      files.first { ($0["path"] as? String)?.hasSuffix("run.sh") == true })
    let before = try #require(changedScript["before"] as? [String: Any])
    let after = try #require(changedScript["after"] as? [String: Any])
    #expect(before["base64"] as? String == after["base64"] as? String)
    #expect(before["executable"] as? Bool == false)
    #expect(after["executable"] as? Bool == true)
    let preview = try fixture.success(command).stdout
    #expect(
      preview.hasPrefix(
        "~ changed  pdf  local:\(fixture.source.path)  1.2.0 (\(oldRevision.prefix(7))) -> 1.3.0 (\(newRevision.prefix(7)))\n"
      ))
    #expect(preview.components(separatedBy: "mode pdf/run.sh: 644 -> 755\n").count == 2)
    #expect(!preview.contains("--- a/") && !preview.contains("= repinned"))
    let applied = try fixture.success(command + ["--apply"]).stdout
    #expect(
      applied.hasSuffix(
        "Updated pdf for claude-code, codex: 1.2.0 (\(oldRevision.prefix(7))) -> 1.3.0 (\(newRevision.prefix(7))).\n"
      ))
    let installed = fixture.project.appendingPathComponent(".agents/skills/pdf/run.sh")
    #expect(FileManager.default.isExecutableFile(atPath: installed.path))
    try fixture.git(["tag", "1.4.0"])
    let repinned = try fixture.success(command + ["--apply"]).stdout
    #expect(repinned.hasPrefix("= repinned  pdf  "))
    #expect(
      repinned.contains("1.3.0 (\(newRevision.prefix(7))) -> 1.4.0 (\(newRevision.prefix(7)))"))
    #expect(
      repinned.hasSuffix(
        "Updated pdf for claude-code, codex: 1.3.0 (\(newRevision.prefix(7))) -> 1.4.0 (\(newRevision.prefix(7))).\n"
      ))
    #expect(!repinned.contains("mode pdf/"))
    var declaration = try fixture.declaration()
    declaration["skills"] = [String: Any]()
    try JSONSerialization.data(withJSONObject: declaration).write(to: fixture.state("agents.json"))
    let removal = try fixture.success(command + ["--json"]).json()
    let removedSkill = try #require((removal["skills"] as? [[String: Any]])?.first)
    #expect(removedSkill["oldVersion"] as? String == "1.4.0")
    #expect(removedSkill["newVersion"] == nil)
    let removed = try fixture.success(command + ["--apply"]).stdout
    #expect(removed.hasPrefix("- removed  pdf  "))
    #expect(removed.contains("1.4.0 (\(newRevision.prefix(7))) -> none"))
    #expect(removed.hasSuffix("Removed pdf for claude-code, codex.\n"))
  }

  @Test(arguments: [["skills", "update"], ["update"]])
  func liveMembershipIncludesAddedRemovedAndUnchanged(_ command: [String]) throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    try fixture.success(["skills", "add", fixture.source.path, "pdf", "--mode", "edit"])
    let steady = try fixture.success(command + ["--json"]).json()
    let steadySkill = try #require((steady["skills"] as? [[String: Any]])?.first)
    #expect(steadySkill["changed"] as? Bool == false)
    #expect((steadySkill["membership"] as? [Any])?.count == 2)
    try selection(fixture) { $0["agents"] = ["claude-code", "cursor"] }
    let report = try fixture.success(command + ["--json"]).json()
    let skill = try #require((report["skills"] as? [[String: Any]])?.first)
    #expect(skill["oldVersion"] == nil && skill["newVersion"] == nil)
    #expect(skill["oldRevision"] == nil && skill["newRevision"] == nil)
    #expect(skill["lockMissing"] as? Bool == false)
    let rows = try #require(skill["membership"] as? [[String: Any]])
    #expect(rows.compactMap { $0["agent"] as? String } == ["claude-code", "codex", "cursor"])
    #expect(rows[0]["before"] as? [String: String] == ["kind": "installed", "mode": "edit"])
    #expect(rows[0]["after"] as? [String: String] == ["kind": "installed", "mode": "edit"])
    #expect(rows[1]["after"] as? [String: String] == ["kind": "absent"])
    #expect(rows[2]["before"] as? [String: String] == ["kind": "absent"])
    #expect(
      rows[2]["path"] as? String
        == fixture.project.resolvingSymlinksInPath().appendingPathComponent(".agents/skills/pdf")
        .path)
    let preview = try fixture.success(command).stdout
    #expect(preview.hasPrefix("~ changed  pdf  local:\(fixture.source.path)\n"))
    #expect(preview.contains("  = unchanged  claude-code (edit)  .claude/skills/pdf\n"))
    #expect(preview.contains("  - removed  codex (edit)  .agents/skills/pdf\n"))
    #expect(preview.contains("  + added  cursor (edit)  .agents/skills/pdf\n"))
    let applied = try fixture.success(command + ["--apply"]).stdout
    #expect(
      applied.hasSuffix(
        "Removed pdf for codex.\nAdded pdf for cursor.\nUpdated pdf for claude-code.\n"))
    #expect(
      FileManager.default.fileExists(
        atPath: fixture.project.appendingPathComponent(".agents/skills/pdf").path))
  }

  @Test(arguments: [["skills", "update"], ["update"]])
  func missingLockReportsUnrecordedMembershipWithoutAdoption(_ command: [String]) throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    try fixture.success([
      "skills", "add", fixture.source.path, "pdf", "--mode", "edit", "--agent", "codex",
    ])
    try FileManager.default.removeItem(at: fixture.state("agents.resolved"))
    let report = try fixture.success(command + ["--json"]).json()
    let skill = try #require((report["skills"] as? [[String: Any]])?.first)
    #expect(skill["lockMissing"] as? Bool == true)
    if command == ["update"] { #expect(report["lockMissing"] as? Bool == true) }
    #expect((skill["files"] as? [Any])?.isEmpty == true)
    let row = try #require((skill["membership"] as? [[String: Any]])?.first)
    #expect(row["before"] as? [String: String] == ["kind": "absent"])
    #expect(row["after"] as? [String: String] == ["kind": "installed", "mode": "edit"])
    let preview = try fixture.success(command).stdout
    #expect(
      preview.hasPrefix(
        "Lock missing: earlier membership is unknown.\n+ new  pdf  "))
    #expect(preview.contains("  + added  codex (edit)  .agents/skills/pdf\n"))
    let failed = try fixture.run(command + ["--apply"])
    #expect(failed.status == 1 && failed.stdout.isEmpty)
    #expect(failed.stderr.contains("this scope does not manage"))
    #expect(!FileManager.default.fileExists(atPath: fixture.state("agents.resolved").path))
  }

  @Test(arguments: [["skills", "update"], ["update"]], ["link", "copy", "edit"])
  func addedSkillsUseMembershipAndAvailablePins(command: [String], mode: String) throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    try fixture.commit()
    try fixture.git(["tag", "1.2.0"])
    try fixture.success(["skills", "add", fixture.source.path, "--all", "--mode", mode])
    try fixture.skill("new")
    try fixture.commit()
    try fixture.git(["tag", "1.3.0"])
    let revision = try fixture.revision()
    let pins = mode == "edit" ? "" : "  none -> 1.3.0 (\(revision))"
    let rows =
      "+ new  new  local:\(fixture.source.path)\(pins)\n"
      + "  + added  claude-code (\(mode))  .claude/skills/new\n"
      + "  + added  codex (\(mode))  .agents/skills/new\n"
    let preview = try fixture.success(command).stdout
    #expect(preview.hasPrefix(rows))
    let applied = try fixture.success(command + ["--apply"]).stdout
    #expect(applied.hasPrefix(rows))
    #expect(applied.components(separatedBy: "Added new for claude-code, codex.\n").count == 2)
    #expect(!applied.contains("Updated new"))
  }

  @Test func combinedRecoveryRendersOneFreshPreviewBeforeCompletions() throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    try fixture.instruction()
    try fixture.commit()
    try fixture.success(["skills", "add", fixture.source.path, "pdf"])
    try fixture.success(["instructions", "add", fixture.source.path])
    let before = try fixture.revision()
    try fixture.skill("pdf", body: "New skill")
    try fixture.instruction(body: "New instruction")
    try fixture.commit()
    let after = try fixture.revision()
    let preview = try fixture.success(["update"]).stdout
    let notice = "Preview only. Run again with --apply to write these changes.\n"
    try Data("partial journal".utf8).write(to: fixture.state("transaction.new"))
    let read = try fixture.run(["update", "--json"])
    #expect(read.status == 1 && read.stdout.isEmpty)
    let applied = try fixture.run(["update", "--apply"])
    #expect(applied.status == 0)
    #expect(applied.stderr == "Recovered interrupted transaction at .agent; retrying once.\n")
    #expect(
      applied.stdout == String(preview.dropLast(notice.count))
        + "Updated pdf for claude-code, codex: \(before) -> \(after).\nUpdated AGENTS.md.\n")
    #expect(try fixture.success(["update"]).stdout == "No changes.\n")
  }

  @Test func combinedReportIncludesPromptOnlyRepins() throws {
    let fixture = try CLIFixture()
    try fixture.instruction()
    try fixture.commit()
    try fixture.success(["instructions", "add", fixture.source.path])
    try fixture.declarePrompt()
    var declaration = try fixture.declaration()
    var instructions = try #require(declaration["instructions"] as? [String: Any])
    instructions["sections"] = [String]()
    declaration["instructions"] = instructions
    try JSONSerialization.data(withJSONObject: declaration).write(to: fixture.state("agents.json"))
    try fixture.success(["update", "--apply"])
    let locked = try Data(contentsOf: fixture.state("agents.resolved"))
    try Data("Unrelated source content\n".utf8).write(
      to: fixture.source.appendingPathComponent("README.md"))
    try fixture.commit()
    let report = try fixture.success(["update", "--json"]).json()
    #expect(report["changed"] as? Bool == true)
    #expect((report["skills"] as? [Any])?.isEmpty == true)
    let changes = try #require(report["instructions"] as? [String: Any])
    #expect((changes["targets"] as? [Any])?.isEmpty == true)
    #expect((changes["changedPrompts"] as? [Any])?.isEmpty == true)
    #expect(
      try fixture.success(["update"]).stdout
        == "Preview only. Run again with --apply to write these changes.\n")
    try fixture.success(["update", "--apply"])
    #expect(try Data(contentsOf: fixture.state("agents.resolved")) != locked)
    #expect(try fixture.success(["update"]).stdout == "No changes.\n")
  }

  @Test func missingTargetKeepsManagedMembership() throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    try fixture.commit()
    try fixture.success([
      "skills", "add", fixture.source.path, "pdf", "--mode", "copy", "--agent", "codex",
    ])
    let target = fixture.project.appendingPathComponent(".agents/skills/pdf")
    try FileManager.default.removeItem(at: target)
    let report = try fixture.success(["update", "--json"]).json()
    let skill = try #require((report["skills"] as? [[String: Any]])?.first)
    let row = try #require((skill["membership"] as? [[String: Any]])?.first)
    #expect(row["before"] as? [String: String] == ["kind": "installed", "mode": "copy"])
    #expect(row["after"] as? [String: String] == ["kind": "installed", "mode": "copy"])
    let applied = try fixture.success(["update", "--apply"]).stdout
    #expect(applied.hasPrefix("~ changed  pdf  "))
    #expect(applied.contains("  = unchanged  codex (copy)  .agents/skills/pdf\n"))
    #expect(FileManager.default.fileExists(atPath: target.path))
  }

  @Test func combinedApplyFailurePreservesStateAndExplainsDisposition() throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    try fixture.instruction()
    try fixture.commit()
    try fixture.success(["skills", "add", fixture.source.path, "pdf"])
    try fixture.success(["instructions", "add", fixture.source.path])
    let lock = try Data(contentsOf: fixture.state("agents.resolved"))
    let target = fixture.project.appendingPathComponent("AGENTS.md")
    try fixture.skill("pdf", body: "New skill")
    try fixture.instruction(body: "New instruction")
    try fixture.commit()
    let environment = RuntimeEnvironment(
      projectDirectory: fixture.project, homeDirectory: fixture.home,
      environment: fixture.environment)
    do {
      try UpdateOperations.withPreparedUpdate(environment: environment) { update in
        #expect(update.report.hasChanges)
        try Data("Concurrent edit\n".utf8).write(to: target)
        _ = try update.apply()
      }
      Issue.record("Expected precondition failure")
    } catch let error as UpdateApplyError {
      #expect(error.disposition == .unchanged)
      #expect(
        Terminal.failureMessage(error).hasPrefix(
          "Update failed; no update was applied.\n"))
      #expect(Terminal.failureMessage(error).contains(String(describing: error.underlyingError)))
      #expect(
        Terminal.failureRemedy(error, command: Update())
          == Terminal.failureRemedy(error.underlyingError, command: Update()))
    }
    #expect(try Data(contentsOf: fixture.state("agents.resolved")) == lock)
    #expect(try String(contentsOf: target, encoding: .utf8) == "Concurrent edit\n")
    #expect(
      try String(
        contentsOf: fixture.project.appendingPathComponent(".agents/skills/pdf/SKILL.md"),
        encoding: .utf8
      ).contains("Original content"))
  }

  @Test(arguments: [
    (
      UpdateApplyDisposition.unchanged, "Update failed; no update was applied.",
      "Check the scope's agents.json, agents.resolved, and recovery journal."
    ),
    (
      .committed, "Update committed, but a later step failed.",
      "Run 'agents doctor' in the same scope to inspect the committed update before retrying."
    ),
    (
      .recoveryRequired, "Update failed; recovery is required.",
      "Run 'agents update --apply' in the same scope to recover and prepare a fresh update."
    ),
  ])
  func applyFailureOutput(disposition: UpdateApplyDisposition, outcome: String, remedy: String) {
    let underlying = CoreError.invalidState("fixture failure")
    let message = Terminal.updateFailureMessage(disposition, underlyingError: underlying)
    let advice = Terminal.updateFailureRemedy(
      disposition, underlyingError: underlying, command: Update())
    #expect(
      Terminal.formatError(message, remedy: advice)
        == "Error: \(outcome)\n  Invalid state: fixture failure.\n  \(remedy)\n")
  }

  private func selection(_ fixture: CLIFixture, edit: (inout [String: Any]) -> Void) throws {
    var declaration = try fixture.declaration()
    var skills = try #require(declaration["skills"] as? [String: [String: Any]])
    let alias = try #require(skills.keys.first)
    var value = try #require(skills[alias])
    edit(&value)
    skills[alias] = value
    declaration["skills"] = skills
    try JSONSerialization.data(withJSONObject: declaration).write(to: fixture.state("agents.json"))
  }
}
