import AgentsCore
import AgentsInstructions
import AgentsSkills
import AgentsUpdates
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
        Terminal.write("Restored instructions in \(location.paths.path(target.url.path)).\n")
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
        beforeApply: { results in
          Terminal.differences(results, paths: location.paths)
        })
    }
  }

  func finishSkills(_ results: [UpdateResult]) {
    if apply {
      Terminal.updatedSkills(results)
    } else {
      Terminal.differences(results, paths: location.paths)
    }
  }

  func updateInstructions(agents: [AgentID]? = nil, replace: Bool = false) throws
    -> InstructionUpdateReport
  {
    try withRecovery {
      try InstructionOperations.updateInstalled(
        scope: location.scope, agents: agents, apply: apply, replace: replace,
        beforeApply: { result in
          Terminal.instructionDifferences(result, paths: location.paths)
        })
    }
  }

  func finishInstructions(_ result: InstructionUpdateReport) {
    if apply {
      Terminal.updatedInstructions(result, paths: location.paths)
    } else {
      Terminal.instructionDifferences(result, paths: location.paths)
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
    let paths = options.location.paths
    if options.apply {
      let receipt = try withRecovery {
        try UpdateOperations.withPreparedUpdate(scope: options.location.scope) { update in
          Terminal.updateDifferences(update.report, paths: paths)
          return try update.apply()
        }
      }
      Terminal.updatedSkills(receipt.report.skills)
      Terminal.updatedInstructions(receipt.report.instructions, paths: paths)
      Terminal.promptReminder(receipt.report.instructions.changedPrompts)
    } else {
      let report = try UpdateOperations.preview(scope: options.location.scope)
      if options.json {
        try Terminal.json(UpdateReport(report))
      } else {
        Terminal.updateDifferences(report, paths: paths)
        options.previewNotice(changed: report.hasChanges)
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
    let skills = try options.updateSkills(names: names)
    if options.json {
      try Terminal.json(
        UpdateReport(scope: options.location.scope.rawValue, results: skills))
    } else {
      options.finishSkills(skills)
      options.previewNotice(changed: skills.contains(where: \.changed))
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
          scope: location.scope.rawValue, report: report, instructions: instructions,
          environment: runtime))
    }
    let report = DoctorOutput(roots: reports)
    if json {
      try Terminal.json(report)
    } else {
      for root in reports {
        Terminal.write("\(location.paths.path(root.root)) (\(root.scope))\n")
        if root.checks.isEmpty { Terminal.write("  No problems found.\n") }
        for check in root.checks {
          let path = check.path.map { " (\(location.paths.path($0)))" } ?? ""
          Terminal.write(
            "  \(check.kind) \(check.status): \(Terminal.line(check.message))\(path)\n")
        }
      }
    }
    if !report.ok { throw ExitCode.failure }
  }
}
