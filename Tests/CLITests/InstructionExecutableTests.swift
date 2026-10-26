import AgentsInstructions
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
    try fixture.success(
      [
        "instructions", "add", fixture.source.path, "canonical-artifacts", "--agent", "codex",
        "--branch", "main",
      ] + arguments)
    let original = try String(contentsOf: target, encoding: .utf8)
    #expect(original == generated(["# Canonical Artifacts\n\nOriginal instructions"]))
    let list = try fixture.success(["instructions", "list", "--json"] + arguments).json()
    #expect(Set(list.keys) == ["schemaVersion", "kind", "scope", "sections", "targets", "prompts"])
    #expect(list["schemaVersion"] as? Int == 1 && list["kind"] as? String == "installed")
    let sections = try #require(list["sections"] as? [[String: Any]])
    #expect(sections.count == 1 && sections.first?["name"] as? String == "canonical-artifacts")
    let targets = try #require(list["targets"] as? [[String: Any]])
    #expect(targets.first?["agents"] as? [String] == ["codex"])
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
    #expect(json["schemaVersion"] as? Int == 2)
    let changes = try #require(json["instructions"] as? [String: Any])
    #expect(changes["changedPrompts"] as? [String] == ["weekly"])
    let files = try #require(changes["targets"] as? [[String: Any]])
    let before = try #require(files.first?["before"] as? [String: String])
    #expect(Data(base64Encoded: try #require(before["base64"])) == Data(drift.utf8))
    #expect(files.first?["drift"] as? String == "drifted")
    #expect(files.first?["foreign"] as? Bool == false)
    #expect(try Data(contentsOf: fixture.state("agents.json", scope: scope)) == declaration)
    #expect(try Data(contentsOf: fixture.state("agents.resolved", scope: scope)) == lock)
    #expect(try Data(contentsOf: target) == Data(drift.utf8))
    let applied = try fixture.success(["instructions", "update", "--apply"] + arguments)
    let diffIndex = try #require(applied.stdout.range(of: "+Updated instructions")?.lowerBound)
    let appliedIndex = try #require(
      applied.stdout.range(of: "Updated ")?.lowerBound)
    #expect(diffIndex < appliedIndex)
    #expect(applied.stdout.contains("Changed ChatGPT prompt weekly."))
    let expected = try Data(contentsOf: target)
    #expect(expected == Data(generated(["# Canonical Artifacts\n\nUpdated instructions"]).utf8))
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
    #expect(!FileManager.default.fileExists(atPath: target.path))
    let empty = try fixture.success(["instructions", "list", "--json"] + arguments).json()
    #expect((empty["sections"] as? [Any])?.isEmpty == true)
    #expect((empty["targets"] as? [Any])?.isEmpty == true)
    #expect((empty["prompts"] as? [Any])?.isEmpty == true)
    let missingPrompt = try fixture.run(
      ["instructions", "render", "chatgpt", "weekly"] + arguments)
    #expect(missingPrompt.status == 1 && missingPrompt.stdout.isEmpty)
  }

  @Test func sourceSelectionAndTakeover() throws {
    let fixture = try CLIFixture()
    try fixture.instruction(container: "collection/instructions")
    try fixture.instruction("other", heading: "Other Rules", container: "collection/instructions")
    try fixture.commit()
    let sourceArguments = [fixture.source.path, "--path", "collection"]
    let choices = try fixture.success(["instructions", "add"] + sourceArguments)
    #expect(choices.stdout.contains("canonical-artifacts") && choices.stdout.contains("other"))
    #expect(choices.stdout.contains("Canonical Artifacts rules."))
    #expect(!FileManager.default.fileExists(atPath: fixture.state("agents.json").path))
    let discovered = try fixture.success(["instructions", "list"] + sourceArguments + ["--json"])
      .json()
    #expect(discovered["kind"] as? String == "source")
    let sections = try #require(discovered["sections"] as? [[String: Any]])
    #expect(sections.count == 2 && sections.first?["heading"] as? String == "Canonical Artifacts")
    #expect(sections.first?["level"] as? Int == 1)
    #expect(sections.first?["description"] as? String == "Canonical Artifacts rules.")
    #expect(sections.first?["paths"] as? [String] == [])
    let target = fixture.project.appendingPathComponent("AGENTS.md")
    let custom = "# Guide\n\nHand-written content\n"
    try Data(custom.utf8).write(to: target)
    let add = [
      "instructions", "add", fixture.source.path, "canonical-artifacts", "--path", "collection",
    ]
    let refused = try fixture.run(add)
    #expect(refused.status == 1 && refused.stdout.isEmpty)
    #expect(
      refused.stderr.contains("Files that agents did not generate are in the way: AGENTS.md.")
        && refused.stderr.hasSuffix(
          "\n  Move what those files need into instructions files, then rerun with --replace to take them over.\n"
        ))
    #expect(try String(contentsOf: target, encoding: .utf8) == custom)
    #expect(!FileManager.default.fileExists(atPath: fixture.state("agents.resolved").path))
    let replaced = try fixture.success(add + ["--replace"])
    #expect(replaced.stdout.contains("Take over AGENTS.md, which agents did not generate\n"))
    #expect(replaced.stdout.contains("-Hand-written content"))
    #expect(replaced.stdout.contains("+Original instructions"))
    try fixture.success(["instructions", "add", "source", "other"])
    let declaration = try fixture.declaration()
    let instructions = try #require(declaration["instructions"] as? [String: Any])
    #expect(
      instructions["sections"] as? [String] == ["source:canonical-artifacts", "source:other"])
  }

  @Test func editedTargetsFollowTheLockAndHandWrittenOnesNeedReplace() throws {
    let fixture = try CLIFixture()
    try fixture.instruction()
    try fixture.instruction("other", heading: "Other Rules")
    try fixture.commit()
    try fixture.success([
      "instructions", "add", fixture.source.path, "canonical-artifacts", "other", "--agent",
      "codex",
    ])
    let target = fixture.project.appendingPathComponent("AGENTS.md")
    let original = try Data(contentsOf: target)
    let edited = Data(
      String(decoding: original, as: UTF8.self)
        .replacingOccurrences(of: "Original instructions", with: "Hand edit.").utf8)
    try edited.write(to: target)
    try fixture.success(["install"])
    #expect(try Data(contentsOf: target) == original)
    let handWritten = Data("Hand-written.\n".utf8)
    try handWritten.write(to: target)
    for arguments in [["install"], ["instructions", "remove", "other"]] {
      let refused = try fixture.run(arguments)
      #expect(
        refused.status == 1
          && refused.stderr.hasSuffix(
            "\n  Move what those files need into instructions files, delete them, and retry.\n"
          ))
      #expect(try Data(contentsOf: target) == handWritten)
    }
    try fixture.success(["instructions", "update", "--apply", "--replace"])
    try edited.write(to: target)
    let removed = try fixture.success(["instructions", "remove", "other"])
    #expect(removed.stdout.contains("-Hand edit."))
    #expect(
      try String(contentsOf: target, encoding: .utf8)
        == generated(["# Canonical Artifacts\n\nOriginal instructions"]))
    let kept = Data(
      try String(contentsOf: target, encoding: .utf8)
        .replacingOccurrences(of: "Original instructions", with: "Hand edit.").utf8)
    try kept.write(to: target)
    let left = try fixture.success(["instructions", "remove", "canonical-artifacts"])
    #expect(
      left.stdout.contains(
        "Left AGENTS.md in place because it differs from its generated version\n"))
    #expect(try Data(contentsOf: target) == kept)
    for arguments in [["install"], ["instructions", "remove", "other"]] {
      let invalid = try fixture.run(arguments + ["--replace"])
      #expect(invalid.status == 64 && invalid.stderr.contains("Unknown option '--replace'"))
    }
  }

  @Test func addNamesTheSectionsEachTargetReceives() throws {
    let fixture = try CLIFixture()
    let render = fixture.project.appendingPathComponent("Sources/Render")
    try FileManager.default.createDirectory(at: render, withIntermediateDirectories: true)
    let own = fixture.project.appendingPathComponent(".agent/instructions")
    try FileManager.default.createDirectory(at: own, withIntermediateDirectories: true)
    try Data("---\ndescription: Guide.\n---\n# Guide\n\nRead the README.\n".utf8).write(
      to: own.appendingPathComponent("guide.md"))
    try Data(
      "---\ndescription: Rendering.\npaths: [\"Sources/Render/**\"]\n---\n# Rendering\n\nKeep frames stable.\n"
        .utf8
    ).write(to: own.appendingPathComponent("render.md"))
    let added = try fixture.success([
      "instructions", "add", ".", "render", "guide", "--agent", "codex",
    ])
    #expect(
      added.stdout
        == "Added guide to AGENTS.md (codex).\nAdded render to Sources/Render/AGENTS.md (codex).\n")
    #expect(
      try String(contentsOf: render.appendingPathComponent("AGENTS.md"), encoding: .utf8)
        == generated([
          "# Rendering\n\nApplies when working on files matching `Sources/Render/**`.\n\nKeep frames stable."
        ]))
  }

  @Test func updateTakesOverHandWrittenTargetsOnlyWithReplace() throws {
    let fixture = try CLIFixture()
    try fixture.instruction()
    try fixture.commit()
    try fixture.success(["instructions", "add", fixture.source.path, "--agent", "codex"])
    let gemini = fixture.project.appendingPathComponent("GEMINI.md")
    let custom = Data("# Gemini\n\nHand-written.\n".utf8)
    try custom.write(to: gemini)
    let arguments = ["instructions", "update", "--agent", "codex", "--agent", "gemini-cli"]
    let preview = try fixture.success(arguments + ["--json"]).json()
    let changes = try #require(preview["instructions"] as? [String: Any])
    let targets = try #require(changes["targets"] as? [[String: Any]])
    #expect(targets.first { $0["target"] as? String == "GEMINI.md" }?["foreign"] as? Bool == true)
    let refused = try fixture.run(arguments + ["--apply"])
    #expect(
      refused.status == 1
        && refused.stderr.hasSuffix(
          "\n  Move what those files need into instructions files, then rerun with --replace to take them over.\n"
        ))
    #expect(try Data(contentsOf: gemini) == custom)
    let usage = try fixture.run(arguments + ["--replace"])
    #expect(usage.status == 64 && usage.stdout.isEmpty)
    let applied = try fixture.success(arguments + ["--apply", "--replace"])
    #expect(applied.stdout.contains("Take over GEMINI.md, which agents did not generate\n"))
    #expect(
      try String(contentsOf: gemini, encoding: .utf8)
        == generated(["# Canonical Artifacts\n\nOriginal instructions"]))
  }

  @Test func ownInstructionsAndExport() throws {
    let fixture = try CLIFixture()
    let created = try fixture.success(["instructions", "init", "guide"])
    #expect(created.stdout == "Created .agent/instructions/guide.md.\n")
    let own = fixture.project.appendingPathComponent(".agent/instructions/guide.md")
    let listed = try fixture.success(["instructions", "list", ".", "--json"]).json()
    let available = try #require((listed["sections"] as? [[String: Any]])?.first)
    #expect((available["section"] as? [String: Any])?["source"] as? String == ".")
    try fixture.success(["instructions", "add", ".", "guide", "--agent", "codex"])
    let target = fixture.project.appendingPathComponent("AGENTS.md")
    #expect(
      try String(contentsOf: target, encoding: .utf8)
        == generated(["# guide\n\nWrite the instructions here."]))
    let declaration = try fixture.declaration()
    #expect((declaration["instructions"] as? [String: Any])?["sections"] as? [String] == ["guide"])
    try Data(
      "---\ndescription: Guide.\n---\n# guide\n\nEdited instructions.\n".utf8
    ).write(to: own)
    let install = try fixture.run(["install"])
    #expect(
      install.status == 1
        && install.stderr.hasSuffix(
          "\n  Run 'agents instructions update --apply' to regenerate targets from the edited file.\n"
        ))
    try fixture.success(["instructions", "update", "--apply"])
    #expect(try String(contentsOf: target, encoding: .utf8).contains("Edited instructions."))
    let other = fixture.root.appendingPathComponent("other")
    try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
    let export = try fixture.success([
      "instructions", "export", "--root", fixture.project.path, "--root", other.path, "--json",
    ]).json()
    #expect(export["schemaVersion"] as? Int == 1)
    let scopes = try #require(export["scopes"] as? [[String: Any]])
    #expect(scopes.map { $0["scope"] as? String } == ["user", "project", "project"])
    #expect(scopes.map { $0["status"] as? String } == ["missingLock", "locked", "missingLock"])
    let mapped = try #require((scopes[1]["targets"] as? [[String: Any]])?.first)
    #expect(
      mapped["target"] as? String == "AGENTS.md" && mapped["agents"] as? [String] == ["codex"])
    let section = try #require((mapped["sections"] as? [[String: Any]])?.first)
    #expect(section["name"] as? String == "guide" && section["source"] as? String == ".")
    #expect(section["path"] as? String == ".agent/instructions/guide.md")
    let human = try fixture.success(["instructions", "export"])
    #expect(human.stdout.contains("  AGENTS.md  codex\n    guide  .\n"))
    let fromHome = try fixture.success(["instructions", "export"], directory: fixture.home)
    #expect(fromHome.stdout == "~ (user)  no lock\n. (project)  no lock\n")
  }

  @Test func recipientOnlyUpdate() throws {
    let fixture = try CLIFixture()
    try fixture.instruction()
    try fixture.commit()
    try fixture.success(["instructions", "add", fixture.source.path, "--agent", "codex"])
    let target = fixture.project.appendingPathComponent("AGENTS.md")
    let bytes = try Data(contentsOf: target)
    let declaration = try Data(contentsOf: fixture.state("agents.json"))
    let lock = try Data(contentsOf: fixture.state("agents.resolved"))
    let arguments = ["instructions", "update", "--agent", "cursor"]
    let recipients = "Recipients of AGENTS.md: codex -> cursor\n"
    let preview = try fixture.success(arguments)
    #expect(preview.stdout.contains(recipients))
    #expect(preview.stdout.contains("Preview only."))
    #expect(!preview.stdout.contains("No instruction changes."))
    #expect(!preview.stdout.contains("--- "))
    let json = try fixture.success(arguments + ["--json"]).json()
    #expect(json["changed"] as? Bool == true)
    let changes = try #require(json["instructions"] as? [String: Any])
    #expect(changes["changed"] as? Bool == true)
    let targets = try #require(changes["targets"] as? [[String: Any]])
    #expect(targets.count == 1)
    let change = try #require(targets.first)
    #expect(
      Set(change.keys) == [
        "target", "path", "changed", "agentsChanged", "beforeAgents", "afterAgents",
        "before", "after", "drift", "foreign",
      ])
    #expect(change["changed"] as? Bool == false && change["agentsChanged"] as? Bool == true)
    #expect(change["beforeAgents"] as? [String] == ["codex"])
    #expect(change["afterAgents"] as? [String] == ["cursor"])
    #expect(change["before"] as? [String: String] == change["after"] as? [String: String])
    #expect(try Data(contentsOf: target) == bytes)
    #expect(try Data(contentsOf: fixture.state("agents.json")) == declaration)
    #expect(try Data(contentsOf: fixture.state("agents.resolved")) == lock)
    let applied = try fixture.success(arguments + ["--apply"])
    #expect(applied.stdout.contains(recipients))
    #expect(!applied.stdout.contains("Updated AGENTS.md."))
    #expect(try Data(contentsOf: target) == bytes)
    let clean = try fixture.success(["instructions", "update", "--json"]).json()
    #expect(clean["changed"] as? Bool == false)
    let cleanChanges = try #require(clean["instructions"] as? [String: Any])
    #expect(cleanChanges["changed"] as? Bool == false)
    let cleanTargets = try #require(cleanChanges["targets"] as? [[String: Any]])
    #expect(cleanTargets.first?["beforeAgents"] as? [String] == ["cursor"])
    #expect(cleanTargets.first?["afterAgents"] as? [String] == ["cursor"])
    #expect(cleanTargets.first?["agentsChanged"] as? Bool == false)
    let unchanged = try fixture.success(arguments)
    #expect(unchanged.stdout == "No instruction changes.\n")
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
    let changes = try #require(preview["instructions"] as? [String: Any])
    let targets = try #require(changes["targets"] as? [[String: Any]])
    let added = try #require(targets.first { $0["target"] as? String == "GEMINI.md" })
    #expect(added["beforeAgents"] is NSNull)
    #expect(added["afterAgents"] as? [String] == ["gemini-cli"])
    #expect(added["agentsChanged"] as? Bool == true && added["before"] == nil)
    let removed = try #require(targets.first { $0["target"] as? String == "AGENTS.md" })
    #expect(removed["beforeAgents"] as? [String] == ["claude-code", "codex"])
    #expect(removed["afterAgents"] as? [String] == [])
    let human = try fixture.success(["instructions", "update", "--agent", "gemini-cli"])
    for (name, recipients) in [
      ("AGENTS.md", "claude-code, codex -> none"), ("GEMINI.md", "none -> gemini-cli"),
    ] {
      let path = name
      let recipientsIndex = try #require(
        human.stdout.range(of: "Recipients of \(path): \(recipients)\n")?.lowerBound)
      let header = name == "GEMINI.md" ? "+++ b/\(path)\n" : "--- a/\(path)\n"
      let diffIndex = try #require(human.stdout.range(of: header)?.lowerBound)
      #expect(recipientsIndex < diffIndex)
    }
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
        $0["kind"] as? String == "instructions" && $0["id"] as? String == "drift"
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
    #expect(preview["schemaVersion"] as? Int == 2 && preview["changed"] as? Bool == true)
    #expect((preview["skills"] as? [[String: Any]])?.first?["changed"] as? Bool == true)
    #expect(
      (preview["instructions"] as? [String: Any])?["changedPrompts"] as? [String] == ["weekly"])
    let applied = try fixture.success(["update", "--apply"])
    let skillsIndex = try #require(
      applied.stdout.range(of: "Updated demo for codex:")?.lowerBound)
    let instructionsIndex = try #require(
      applied.stdout.range(of: "~ changed  canonical-artifacts (instructions)")?.lowerBound)
    #expect(instructionsIndex < skillsIndex)
    #expect(applied.stdout.contains("Changed ChatGPT prompt weekly."))
    #expect(try String(contentsOf: skill, encoding: .utf8).contains("Updated skill"))
    #expect(try String(contentsOf: target, encoding: .utf8).contains("Updated section"))
    let clean = try fixture.success(["update", "--json"]).json()
    #expect(clean["changed"] as? Bool == false)
    let steadyInstall = try fixture.success(["install", "--json"]).json()
    #expect((steadyInstall["instructions"] as? [String: Any])?["changed"] as? Bool == false)
  }

  @Test func combinedPreparationFailureLeavesSkillsUnchanged() throws {
    let fixture = try CLIFixture()
    try fixture.skill("pdf")
    try fixture.instruction()
    try fixture.commit()
    try fixture.success(["skills", "add", fixture.source.path, "pdf"])
    try fixture.success(["instructions", "add", fixture.source.path])
    let target = fixture.project.appendingPathComponent("AGENTS.md")
    let generatedTarget = try Data(contentsOf: target)
    try Data("# Canonical Artifacts\n\nNo front matter.\n".utf8).write(
      to: fixture.source.appendingPathComponent("instructions/canonical-artifacts.md"))
    try fixture.skill("pdf", body: "Updated content")
    try fixture.commit()
    let lock = try Data(contentsOf: fixture.state("agents.resolved"))
    for arguments in [["update", "--apply"], ["update", "--json"]] {
      let failed = try fixture.run(arguments)
      #expect(failed.status == 1 && !failed.stderr.isEmpty)
      #expect(failed.stdout.isEmpty)
      for path in [".agents/skills/pdf/SKILL.md", ".claude/skills/pdf/SKILL.md"] {
        #expect(
          try String(contentsOf: fixture.project.appendingPathComponent(path), encoding: .utf8)
            .contains("Original content"))
      }
      #expect(try Data(contentsOf: target) == generatedTarget)
      #expect(try Data(contentsOf: fixture.state("agents.resolved")) == lock)
    }
  }

  @Test func instructionDoctorErrorsAndFailedJSON() throws {
    let fixture = try CLIFixture()
    try fixture.instruction(body: "Run [the checks](CONTRIBUTING.md).")
    try fixture.commit()
    let contributing = fixture.project.appendingPathComponent("CONTRIBUTING.md")
    try Data("Checks.\n".utf8).write(to: contributing)
    try fixture.success(["instructions", "add", fixture.source.path, "--agent", "codex"])
    try FileManager.default.removeItem(at: contributing)
    let doctor = try fixture.run(["doctor", "--json"])
    #expect(doctor.status == 1 && doctor.stderr.isEmpty)
    let report = try doctor.json()
    #expect(report["ok"] as? Bool == false)
    let roots = try #require(report["roots"] as? [[String: Any]])
    let checks = try #require(roots.first?["checks"] as? [[String: Any]])
    #expect(
      checks.contains {
        $0["id"] as? String == "invalidLink" && $0["status"] as? String == "error"
      })
    let failed = try fixture.run(["install", "--json"])
    #expect(failed.status == 1 && failed.stdout.isEmpty)
    #expect(failed.stderr.split(separator: "\n").dropFirst().allSatisfy { $0.hasPrefix("  ") })
    #expect(
      failed.stderr.hasSuffix(
        "\n  Link only to files in the checkout being written, or name the file in text without a link.\n"
      ))
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
    let file = fixture.project.appendingPathComponent(".agent/instructions/new-rules.md")
    #expect(
      try String(contentsOf: file, encoding: .utf8)
        == "---\ndescription: Describe what these instructions make the agent do.\n---\n# new-rules\n\nWrite the instructions here.\n"
    )
    let duplicate = try fixture.run(["instructions", "init", "new-rules"])
    #expect(duplicate.status == 1 && duplicate.stderr.contains("already exists"))
  }

  @Test(arguments: [
    ["instructions"], ["instructions", "--help"], ["instructions", "add", "--help"],
    ["instructions", "list", "--help"], ["instructions", "remove", "--help"],
    ["instructions", "update", "--help"], ["instructions", "render"],
    ["instructions", "render", "--help"], ["instructions", "render", "chatgpt", "--help"],
    ["instructions", "init", "--help"], ["instructions", "export", "--help"],
    ["help", "instructions", "render", "chatgpt"],
  ])
  func help(_ arguments: [String]) throws {
    let fixture = try CLIFixture()
    let result = try fixture.success(arguments)
    #expect(result.stdout.contains("USAGE:") && !result.stdout.contains("--version"))
    if arguments == ["instructions", "render"] || arguments == ["instructions", "render", "--help"]
    {
      #expect(
        result.stdout.contains("OVERVIEW: Print a ChatGPT prompt from the locked sections."))
    }
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
    #expect(result.stderr.split(separator: "\n").dropFirst().allSatisfy { $0.hasPrefix("  ") })
    #expect(result.stderr.hasSuffix("\n  Run 'agents --help' for usage.\n"))
  }
}

/// A generated target holding these section bodies.
func generated(_ sections: [String]) -> String {
  Instructions.notice + "\n\n" + sections.joined(separator: "\n\n") + "\n"
}

extension CLIFixture {
  func instruction(
    _ name: String = "canonical-artifacts", heading: String = "Canonical Artifacts",
    body: String = "Original instructions", container: String = "instructions"
  ) throws {
    let directory = source.appendingPathComponent(container)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("---\ndescription: \(heading) rules.\n---\n# \(heading)\n\n\(body)\n".utf8).write(
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
