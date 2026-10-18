import AgentsCore
import AgentsInstructions
import AgentsSkills
import ArgumentParser
import Foundation

struct Install: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "install",
    abstract: "Restore skills and instructions using exact pins and recipients from the lock.")

  @OptionGroup var location: ScopeOptions
  @Flag(help: "Print the versioned JSON report.") var json = false

  func run() throws {
    let report = try withRecovery {
      try SkillOperations.installResolvedReport(scope: location.scope)
    }
    if !json {
      if report.installed.isEmpty {
        Terminal.write("No locked skills to restore.\n")
      } else {
        Terminal.installed(report.installed)
      }
    }
    let instructions = try withRecovery {
      try InstructionOperations.installResolvedReport(scope: location.scope)
    }
    if json {
      try Terminal.json(
        InstallReport(
          scope: location.scope.rawValue, skills: report.installed,
          instructions: InstructionChanges(instructions)))
      return
    }
    if instructions.targets.isEmpty {
      Terminal.write("No locked instruction targets to restore.\n")
    } else {
      for target in instructions.targets {
        Terminal.write("Restored instructions in \(Terminal.line(target.url.path)).\n")
      }
    }
  }
}

struct UpdateOptions: ParsableArguments {
  @OptionGroup var location: ScopeOptions
  @Flag(help: "Show differences, then replace installations and update the lock.") var apply = false
  @Flag(help: "Print the versioned JSON preview; cannot be used with --apply.") var json = false

  func validate() throws {
    if json && apply { throw ValidationError("--json is for previews; remove --apply or --json") }
  }

  func updateSkills(names: [String] = []) throws -> [UpdateResult] {
    try withRecovery {
      try SkillOperations.updateInstalled(
        scope: location.scope, skillNames: names, apply: apply,
        beforeApply: { Terminal.differences($0) })
    }
  }

  func finishSkills(_ results: [UpdateResult]) {
    if apply {
      Terminal.write("Applied skill update.\n")
    } else {
      Terminal.differences(results)
    }
  }

  func updateInstructions(agents: [AgentID]? = nil) throws -> InstructionUpdateReport {
    try withRecovery {
      try InstructionOperations.updateInstalled(
        scope: location.scope, agents: agents, apply: apply,
        beforeApply: { Terminal.instructionDifferences($0) })
    }
  }

  func finishInstructions(_ result: InstructionUpdateReport) {
    if apply {
      Terminal.write("Applied instruction update.\n")
      Terminal.promptReminder(result.changedPrompts)
    } else {
      Terminal.instructionDifferences(result)
      previewNotice(changed: result.hasChanges)
    }
  }

  func previewNotice(changed: Bool) {
    if !apply && changed {
      Terminal.write("Preview only. Run again with --apply to write these changes.\n")
    }
  }
}

struct Update: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "update",
    abstract: "Preview or apply updates to all declared skills and instructions.")
  @OptionGroup var options: UpdateOptions

  func run() throws {
    let skills = try options.updateSkills()
    if !options.json { options.finishSkills(skills) }
    let instructions = try options.updateInstructions()
    if options.json {
      try Terminal.json(
        UpdateReport(
          scope: options.location.scope.rawValue, results: skills,
          instructions: InstructionChanges(instructions)))
    } else {
      options.finishInstructions(instructions)
      if !instructions.hasChanges {
        options.previewNotice(changed: skills.contains(where: \.changed))
      }
    }
  }
}

struct UpdateSkills: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "update", abstract: "Preview or apply updates to selected or all declared skills.")
  @Argument(help: "Limit the update to these skill names.") var names: [String] = []
  @OptionGroup var options: UpdateOptions

  func run() throws {
    let results = try options.updateSkills(names: names)
    if options.json {
      try Terminal.json(UpdateReport(scope: options.location.scope.rawValue, results: results))
    } else {
      options.finishSkills(results)
      options.previewNotice(changed: results.contains(where: \.changed))
    }
  }
}

struct Doctor: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "doctor",
    abstract: "Compare skills and instructions with the lock and report problems.",
    discussion:
      "The --agent filter limits skill installation checks. Instructions are audited across the scope's physical targets."
  )
  @OptionGroup var location: ScopeOptions
  @OptionGroup var agents: AgentOptions
  @Option(
    name: .long, parsing: .upToNextOption,
    help: "Audit these project directories read-only. Repeat for several.")
  var root: [String] = []
  @Flag(help: "Print the versioned JSON report.") var json = false

  func validate() throws {
    if !root.isEmpty && location.scope == .user {
      throw ValidationError("--root audits projects; use --scope project or omit --root")
    }
  }

  func run() throws {
    let environment = RuntimeEnvironment()
    let directories = root.isEmpty ? [environment.projectDirectory.path] : root
    var reports: [DoctorRoot] = []
    for directory in directories {
      let project = URL(fileURLWithPath: directory, relativeTo: environment.projectDirectory)
        .standardizedFileURL
      var isDirectory: ObjCBool = false
      guard FileManager.default.fileExists(atPath: project.path, isDirectory: &isDirectory),
        isDirectory.boolValue
      else {
        throw CoreError.notFound("project directory \(project.path); provide an existing --root")
      }
      let runtime = RuntimeEnvironment(
        projectDirectory: project, homeDirectory: environment.homeDirectory,
        environment: environment.environment)
      let report = try SkillOperations.doctor(
        scope: location.scope, agents: agents.recipients,
        environment: runtime)
      let instructions = try InstructionOperations.doctor(
        scope: location.scope, environment: runtime)
      reports.append(
        DoctorRoot(
          root: location.scope == .user ? environment.homeDirectory.path : project.path,
          scope: location.scope.rawValue, report: report, instructions: instructions))
    }
    let report = DoctorOutput(roots: reports)
    if json {
      try Terminal.json(report)
    } else {
      for root in reports {
        Terminal.write("\(Terminal.line(root.root)) (\(root.scope))\n")
        if root.checks.isEmpty { Terminal.write("  No problems found.\n") }
        for check in root.checks {
          Terminal.write("  \(check.kind) \(check.status): \(Terminal.line(check.message))\n")
        }
      }
    }
    if !report.ok { throw ExitCode.failure }
  }
}
