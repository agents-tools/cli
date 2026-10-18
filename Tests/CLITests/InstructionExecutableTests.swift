import Foundation
import Testing

@testable import CLI

struct InstructionExecutableTests {
  @Test(arguments: ["project", "user"])
  func lifecycle(_ scope: String) throws {
    let fixture = try CLIFixture()
    let arguments = ["--scope", scope]
    try fixture.instruction()
    try fixture.commit()
    let target =
      scope == "project"
      ? fixture.project.appendingPathComponent("AGENTS.md")
      : fixture.home.appendingPathComponent(".codex/AGENTS.md")
    try FileManager.default.createDirectory(
      at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    let custom =
      "# Project Guide\n\nLocal introduction.\n\n## Local Rules\n\nKeep custom content.\n"
    try Data(custom.utf8).write(to: target)
    try fixture.success(
      [
        "instructions", "add", fixture.source.path, "canonical-artifacts", "--agent", "codex",
        "--branch", "main",
      ] + arguments)
    let original = try String(contentsOf: target, encoding: .utf8)
    #expect(original.contains("## Canonical Artifacts\n\nOriginal instructions"))
    #expect(original.hasPrefix("# Project Guide\n\nLocal introduction.\n"))
    #expect(original.hasSuffix("## Local Rules\n\nKeep custom content.\n"))
    let list = try fixture.success(["instructions", "list", "--json"] + arguments).json()
    #expect(Set(list.keys) == ["schemaVersion", "kind", "scope", "sections", "targets", "prompts"])
    #expect(list["schemaVersion"] as? Int == 1 && list["kind"] as? String == "installed")
    let sections = try #require(list["sections"] as? [[String: Any]])
    #expect(sections.count == 1 && sections.first?["name"] as? String == "canonical-artifacts")
    let targets = try #require(list["targets"] as? [[String: Any]])
    #expect(targets.first?["agents"] as? [String] == ["codex"])
    #expect(targets.first?["created"] as? Bool == false)
    let humanList = try fixture.success(["instructions", "list"] + arguments)
    #expect(humanList.stdout.contains("canonical-artifacts") && humanList.stdout.contains("Target"))
    let drift = original.replacingOccurrences(of: "Original instructions", with: "Manual drift")
    try Data(drift.utf8).write(to: target)
    let doctor = try fixture.success(["doctor", "--json"] + arguments).json()
    let roots = try #require(doctor["roots"] as? [[String: Any]])
    let checks = try #require(roots.first?["checks"] as? [[String: Any]])
    #expect(
      checks.contains { $0["kind"] as? String == "instructions" && $0["id"] as? String == "drift" })
    try fixture.instruction(body: "Updated instructions")
    try fixture.commit()
    try fixture.declarePrompt(scope: scope)
    let declaration = try Data(contentsOf: fixture.state("agents.json", scope: scope))
    let lock = try Data(contentsOf: fixture.state("agents.resolved", scope: scope))
    let preview = try fixture.success(["instructions", "update"] + arguments)
    #expect(
      preview.stdout.contains("-Manual drift") && preview.stdout.contains("+Updated instructions"))
    #expect(preview.stdout.contains("Changed ChatGPT prompt weekly."))
    let json = try fixture.success(["instructions", "update", "--json"] + arguments).json()
    #expect(Set(json.keys) == ["schemaVersion", "scope", "changed", "instructions"])
    let changes = try #require(json["instructions"] as? [String: Any])
    #expect(changes["changedPrompts"] as? [String] == ["weekly"])
    let files = try #require(changes["targets"] as? [[String: Any]])
    let before = try #require(files.first?["before"] as? [String: String])
    #expect(Data(base64Encoded: try #require(before["base64"])) == Data(drift.utf8))
    #expect(files.first?["drift"] as? String == "drifted")
    #expect(try Data(contentsOf: fixture.state("agents.json", scope: scope)) == declaration)
    #expect(try Data(contentsOf: fixture.state("agents.resolved", scope: scope)) == lock)
    #expect(try Data(contentsOf: target) == Data(drift.utf8))
    let applied = try fixture.success(["instructions", "update", "--apply"] + arguments)
    let diffIndex = try #require(applied.stdout.range(of: "+Updated instructions")?.lowerBound)
    let appliedIndex = try #require(
      applied.stdout.range(of: "Applied instruction update.")?.lowerBound)
    #expect(diffIndex < appliedIndex)
    #expect(
      applied.stdout.contains("Re-paste changed ChatGPT prompts")
        && applied.stdout.contains("weekly"))
    let expected = try Data(contentsOf: target)
    let updatedLock = try Data(contentsOf: fixture.state("agents.resolved", scope: scope))
    try Data(drift.utf8).write(to: target)
    try fixture.success(["install"] + arguments)
    #expect(try Data(contentsOf: target) == expected)
    #expect(try Data(contentsOf: fixture.state("agents.resolved", scope: scope)) == updatedLock)
    let rendered = try fixture.success(["instructions", "render", "chatgpt", "weekly"] + arguments)
    #expect(
      rendered.stdout == "# Canonical Artifacts\n\nUpdated instructions\n\nCustom prompt content.\n"
    )
    try fixture.instruction(body: "Unapplied upstream content")
    try fixture.commit()
    let pinned = try fixture.success(["instructions", "render", "chatgpt", "weekly"] + arguments)
    #expect(pinned.stdout == rendered.stdout)
    try fixture.success(["instructions", "remove", "canonical-artifacts"] + arguments)
    let remainingCustom = try String(contentsOf: target, encoding: .utf8)
    // Core owns the blank lines adjacent to the managed block.
    #expect(
      remainingCustom
        == "# Project Guide\n\nLocal introduction.\n## Local Rules\n\nKeep custom content.\n")
    let empty = try fixture.success(["instructions", "list", "--json"] + arguments).json()
    #expect((empty["sections"] as? [Any])?.isEmpty == true)
    #expect((empty["targets"] as? [Any])?.isEmpty == true)
    #expect((empty["prompts"] as? [Any])?.isEmpty == true)
    let missingPrompt = try fixture.run(
      ["instructions", "render", "chatgpt", "weekly"] + arguments)
    #expect(missingPrompt.status == 1 && missingPrompt.stdout.isEmpty)
  }

  @Test func sourceSelectionAndReplacement() throws {
    let fixture = try CLIFixture()
    try fixture.instruction(container: "collection/instructions")
    try fixture.instruction("other", heading: "Other Rules", container: "collection/instructions")
    try fixture.commit()
    let sourceArguments = [fixture.source.path, "--path", "collection"]
    let choices = try fixture.success(["instructions", "add"] + sourceArguments)
    #expect(choices.stdout.contains("canonical-artifacts") && choices.stdout.contains("other"))
    #expect(!FileManager.default.fileExists(atPath: fixture.state("agents.json").path))
    let discovered = try fixture.success(["instructions", "list"] + sourceArguments + ["--json"])
      .json()
    #expect(discovered["kind"] as? String == "source")
    let sections = try #require(discovered["sections"] as? [[String: Any]])
    #expect(sections.count == 2 && sections.first?["heading"] as? String == "Canonical Artifacts")
    let target = fixture.project.appendingPathComponent("AGENTS.md")
    let custom = "# Guide\n\n## Canonical Artifacts\n\nConflicting custom content\n"
    try Data(custom.utf8).write(to: target)
    let add = [
      "instructions", "add", fixture.source.path, "canonical-artifacts", "--path", "collection",
    ]
    let conflict = try fixture.run(add)
    #expect(conflict.status == 1 && conflict.stdout.isEmpty)
    #expect(
      conflict.stderr.contains("Conflicting custom content")
        && conflict.stderr.contains("--replace"))
    #expect(try String(contentsOf: target, encoding: .utf8) == custom)
    #expect(!FileManager.default.fileExists(atPath: fixture.state("agents.resolved").path))
    let replaced = try fixture.success(add + ["--replace"])
    #expect(replaced.stdout.contains("-Conflicting custom content"))
    #expect(replaced.stdout.contains("+Original instructions"))
    try fixture.success(["instructions", "add", "source", "other"])
    let declaration = try fixture.declaration()
    let instructions = try #require(declaration["instructions"] as? [String: Any])
    #expect(
      instructions["sections"] as? [String] == ["source:canonical-artifacts", "source:other"])
  }

  @Test func claudeForwardingAndRecipientChanges() throws {
    let fixture = try CLIFixture()
    try fixture.instruction()
    try fixture.instruction("other", heading: "Other Rules")
    try fixture.commit()
    let claude = fixture.project.appendingPathComponent("CLAUDE.md")
    let custom = "# Claude Guide\n\nKeep Claude custom content.\n"
    try Data(custom.utf8).write(to: claude)
    try fixture.success([
      "instructions", "add", fixture.source.path, "canonical-artifacts", "other",
      "--agent", "codex", "--agent", "claude-code",
    ])
    let forwarded = try String(contentsOf: claude, encoding: .utf8)
    #expect(forwarded.contains("@AGENTS.md") && forwarded.contains("Keep Claude custom content."))
    let before = try Data(contentsOf: fixture.state("agents.json"))
    let preview = try fixture.success(["instructions", "update", "--agent", "gemini-cli", "--json"])
      .json()
    #expect(preview["changed"] as? Bool == true)
    #expect(try Data(contentsOf: fixture.state("agents.json")) == before)
    try fixture.success(["instructions", "update", "--agent", "gemini-cli", "--apply"])
    #expect(try String(contentsOf: claude, encoding: .utf8) == custom)
    #expect(
      !FileManager.default.fileExists(
        atPath: fixture.project.appendingPathComponent("AGENTS.md").path))
    let gemini = fixture.project.appendingPathComponent("GEMINI.md")
    #expect(try String(contentsOf: gemini, encoding: .utf8).contains("Canonical Artifacts"))
    try fixture.success(["instructions", "remove", "other", "--agent", "codex"])
    #expect(!FileManager.default.fileExists(atPath: gemini.path))
    let remaining = try String(
      contentsOf: fixture.project.appendingPathComponent("AGENTS.md"), encoding: .utf8)
    #expect(remaining.contains("Canonical Artifacts") && !remaining.contains("Other Rules"))
    try fixture.success(["instructions", "remove", "canonical-artifacts"])
    #expect(
      !FileManager.default.fileExists(
        atPath: fixture.project.appendingPathComponent("AGENTS.md").path))
  }

  @Test func combinedLifecycleJSONAndRootAudit() throws {
    let fixture = try CLIFixture()
    try fixture.skill()
    try fixture.instruction()
    try fixture.commit()
    try fixture.success([
      "skills", "add", fixture.source.path, "--mode", "copy", "--agent", "codex",
    ])
    try fixture.success(["instructions", "add", fixture.source.path, "--agent", "codex"])
    try fixture.declarePrompt()
    try fixture.success(["instructions", "update", "--apply"])
    let target = fixture.project.appendingPathComponent("AGENTS.md")
    let skill = fixture.project.appendingPathComponent(".agents/skills/demo/SKILL.md")
    let originalTarget = try Data(contentsOf: target)
    try Data("Drifted skill".utf8).write(to: skill)
    try Data().write(to: target)
    let doctor = try fixture.success([
      "doctor", "--root", fixture.project.path, fixture.source.path, "--json",
    ]).json()
    let roots = try #require(doctor["roots"] as? [[String: Any]])
    #expect(roots.count == 2 && (roots[1]["checks"] as? [Any])?.isEmpty == true)
    let checks = try #require(roots.first?["checks"] as? [[String: Any]])
    #expect(checks.first?["kind"] as? String == "skills")
    #expect(
      checks.contains {
        $0["kind"] as? String == "instructions" && $0["id"] as? String == "missingBlock"
      })
    let lock = try Data(contentsOf: fixture.state("agents.resolved"))
    let restored = try fixture.success(["install", "--json"]).json()
    #expect(Set(restored.keys) == ["schemaVersion", "scope", "skills", "instructions"])
    #expect((restored["skills"] as? [[String: Any]])?.first?["name"] as? String == "demo")
    #expect((restored["instructions"] as? [String: Any])?["changed"] as? Bool == true)
    #expect(try Data(contentsOf: target) == originalTarget)
    #expect(try Data(contentsOf: fixture.state("agents.resolved")) == lock)
    try fixture.skill(body: "Updated skill")
    try fixture.instruction(body: "Updated section")
    try fixture.commit()
    let preview = try fixture.success(["update", "--json"]).json()
    #expect(preview["schemaVersion"] as? Int == 1 && preview["changed"] as? Bool == true)
    #expect((preview["skills"] as? [[String: Any]])?.first?["changed"] as? Bool == true)
    #expect(
      (preview["instructions"] as? [String: Any])?["changedPrompts"] as? [String] == ["weekly"])
    let applied = try fixture.success(["update", "--apply"])
    let skillsIndex = try #require(applied.stdout.range(of: "Applied skill update.")?.lowerBound)
    let instructionsIndex = try #require(
      applied.stdout.range(of: "Changed instruction")?.lowerBound)
    #expect(skillsIndex < instructionsIndex)
    #expect(applied.stdout.contains("Re-paste changed ChatGPT prompts"))
    #expect(try String(contentsOf: skill, encoding: .utf8).contains("Updated skill"))
    #expect(try String(contentsOf: target, encoding: .utf8).contains("Updated section"))
    let clean = try fixture.success(["update", "--json"]).json()
    #expect(clean["changed"] as? Bool == false)
    let steadyInstall = try fixture.success(["install", "--json"]).json()
    #expect((steadyInstall["instructions"] as? [String: Any])?["changed"] as? Bool == false)
  }

  @Test func instructionDoctorErrorsAndFailedJSON() throws {
    let fixture = try CLIFixture()
    try fixture.instruction()
    try fixture.commit()
    try fixture.success(["instructions", "add", fixture.source.path, "--agent", "codex"])
    let target = fixture.project.appendingPathComponent("AGENTS.md")
    let original = try String(contentsOf: target, encoding: .utf8)
    try Data((original + "\n<!-- END managed by agents -->\n").utf8).write(to: target)
    let doctor = try fixture.run(["doctor", "--json"])
    #expect(doctor.status == 1 && doctor.stderr.isEmpty)
    let report = try doctor.json()
    #expect(report["ok"] as? Bool == false)
    let roots = try #require(report["roots"] as? [[String: Any]])
    let checks = try #require(roots.first?["checks"] as? [[String: Any]])
    #expect(
      checks.contains {
        $0["id"] as? String == "invalidTarget" && $0["status"] as? String == "error"
      })
    let failed = try fixture.run(["install", "--json"])
    #expect(failed.status == 1 && failed.stdout.isEmpty)
    #expect(failed.stderr.split(separator: "\n").count == 1)
  }

  @Test func emptyScopeReports() throws {
    let fixture = try CLIFixture()
    let installed = try fixture.success(["install", "--json"]).json()
    #expect((installed["skills"] as? [Any])?.isEmpty == true)
    #expect((installed["instructions"] as? [String: Any])?["changed"] as? Bool == false)
    let update = try fixture.success(["update", "--json"]).json()
    #expect(update["changed"] as? Bool == false)
    #expect((update["instructions"] as? [String: Any])?["lockMissing"] as? Bool == true)
    #expect(!FileManager.default.fileExists(atPath: fixture.state("agents.json").path))
    let listing = try fixture.success(["instructions", "list"])
    #expect(listing.stdout == "No managed project instructions.\n")
  }

  @Test func optionHelpStatesDefaultsAndValidValues() throws {
    let fixture = try CLIFixture()
    for name in ["add", "remove", "update"] {
      let help = try fixture.success(["instructions", name, "--help"]).stdout
        .split(whereSeparator: \.isWhitespace).joined(separator: " ")
      #expect(
        help.contains(
          "Set recipients of the scope's section list: codex, claude-code, cursor, gemini-cli or opencode."
        ))
      #expect(
        help.contains(
          "Default: the recorded instruction agents, else the declaration's agents, else codex and claude-code."
        ))
    }
    for command in [["add"], ["list"], ["remove"], ["update"], ["render", "chatgpt"]] {
      let help = try fixture.success(["instructions"] + command + ["--help"]).stdout
        .split(whereSeparator: \.isWhitespace).joined(separator: " ")
      #expect(
        help.contains(
          "Where state lives: project (./.agent) or user (~/.agents). Default: project."))
    }
  }

  @Test func initialization() throws {
    let fixture = try CLIFixture()
    try fixture.success(["instructions", "init", "new-rules"])
    let file = fixture.project.appendingPathComponent("new-rules.md")
    #expect(
      try String(contentsOf: file, encoding: .utf8)
        == "# new-rules\n\nWrite the instructions here.\n")
    let duplicate = try fixture.run(["instructions", "init", "new-rules"])
    #expect(duplicate.status == 1 && duplicate.stderr.contains("already exists"))
  }

  @Test(arguments: [
    ["instructions"], ["instructions", "--help"], ["instructions", "add", "--help"],
    ["instructions", "list", "--help"], ["instructions", "remove", "--help"],
    ["instructions", "update", "--help"], ["instructions", "render"],
    ["instructions", "render", "--help"], ["instructions", "render", "chatgpt", "--help"],
    ["instructions", "init", "--help"], ["help", "instructions", "render", "chatgpt"],
  ])
  func help(_ arguments: [String]) throws {
    let fixture = try CLIFixture()
    let result = try fixture.success(arguments)
    #expect(result.stdout.contains("USAGE:") && !result.stdout.contains("--version"))
  }

  @Test(arguments: [
    ["instructions", "update", "--json", "--apply"], ["instructions", "remove"],
    ["instructions", "render", "chatgpt"], ["instructions", "init"],
    ["help", "instructions", "unknown"], ["instructions", "--version"],
  ])
  func usageFailures(_ arguments: [String]) throws {
    let fixture = try CLIFixture()
    let result = try fixture.run(arguments)
    #expect(result.status == 64 && result.stdout.isEmpty)
    #expect(result.stderr.split(separator: "\n").count == 1)
  }
}

extension CLIFixture {
  func instruction(
    _ name: String = "canonical-artifacts", heading: String = "Canonical Artifacts",
    body: String = "Original instructions", container: String = "instructions"
  ) throws {
    let directory = source.appendingPathComponent(container)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("# \(heading)\n\n\(body)\n".utf8).write(
      to: directory.appendingPathComponent(name + ".md"))
  }

  func declaration(scope: String = "project") throws -> [String: Any] {
    try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: state("agents.json", scope: scope)))
        as? [String: Any])
  }

  func declarePrompt(scope: String = "project") throws {
    var declaration = try declaration(scope: scope)
    var instructions = try #require(declaration["instructions"] as? [String: Any])
    let sections = try #require(instructions["sections"] as? [String])
    instructions["chatgpt"] = ["weekly": ["sections": sections, "append": "prompt-custom.md"]]
    declaration["instructions"] = instructions
    try JSONSerialization.data(withJSONObject: declaration, options: [.sortedKeys]).write(
      to: state("agents.json", scope: scope))
    try Data("Custom prompt content.\n".utf8).write(
      to: (scope == "project" ? project : home).appendingPathComponent("prompt-custom.md"))
  }
}
