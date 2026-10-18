import AgentsCore
import AgentsInstructions
import AgentsSkills
import ArgumentParser
import Foundation

func withRecovery<T>(
  report: (String) -> Void = Terminal.notice,
  _ operation: () throws -> T
) throws -> T {
  do {
    return try operation()
  } catch CoreError.transactionRecovered(let path) {
    report("Recovered interrupted transaction at \(HumanPaths().path(path)); retrying once.")
    return try operation()
  }
}

enum Terminal {
  // Write directly so beforeApply output reaches stdout before core replaces files.
  static func write(_ text: String) { FileHandle.standardOutput.write(Data(text.utf8)) }

  static func notice(_ text: String) {
    FileHandle.standardError.write(Data("\(line(text))\n".utf8))
  }

  static func error(_ text: String) { notice("Error: \(text)") }

  static func line(_ text: String) -> String {
    text.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : String($0) }
      .joined()
  }

  static func failureMessage(_ error: Error, command: any ParsableCommand) -> String {
    let action: String
    switch error {
    case CoreError.transactionRecovered:
      action = "retry the command after other writers finish"
    case CoreError.notFound(let message) where message.hasPrefix("source is not subscribed:"):
      action = "run 'agents watch' to list subscriptions"
    case CoreError.invalidSource("expected a local path or repository URL")
    where command is DiffWatch || command is SeenWatch || command is RemoveWatch:
      action = "run 'agents watch' to list subscriptions"
    case CoreError.invalidSource("invalid watch revision"):
      action = "provide a Git revision that resolves to a commit in the watched source"
    case CoreError.invalidSource("well-known subscriptions do not accept Git revisions"):
      action = "omit --revision to mark the current index seen"
    case CoreError.commandFailed(let message)
    where (command as? SeenWatch)?.revision != nil
      && message.contains(" rev-parse --verify --end-of-options "):
      action = "provide a Git revision that resolves to a commit in the watched source"
    case CoreError.invalidSource, CoreError.notFound:
      action = "check the source, names, and paths"
    case CoreError.unsafePath:
      action = "use a path within the source directory"
    case CoreError.invalidSkill:
      action = "check SKILL.md and existing installations with 'agents doctor'"
    case CoreError.invalidState:
      action = "check the scope's agents.json, agents.resolved, and recovery journal"
    case CoreError.commandFailed:
      action = "check Git access and the source location"
    case InstructionError.conflictingSections:
      if command is AddInstructions {
        action =
          "inspect the differences and rerun with --replace to replace the conflicting custom sections"
      } else {
        action =
          "edit or remove the conflicting custom sections in the target file, or rerun 'agents instructions add' with --replace, then retry"
      }
    case HumanOutputError.undeclaredPrompt:
      action =
        "declare it under instructions.chatgpt in agents.json and run 'agents instructions update --apply'"
    case InstructionError.emptyPrompt:
      action =
        "declare the ChatGPT prompt in agents.json and run 'agents instructions update --apply'"
    case is InstructionError:
      action = "check the instruction source and target Markdown with 'agents doctor'"
    default:
      action = "check the command arguments and filesystem permissions"
    }
    return joiningError(String(describing: error), remedy: action)
  }

  static func json(_ value: some Encodable) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    FileHandle.standardOutput.write(data + Data("\n".utf8))
  }

  static func available(_ skills: [Skill]) {
    if skills.isEmpty { write("No skills found in source.\n") }
    for skill in skills.sorted(by: { $0.name < $1.name }) {
      write("\(line(skill.name))  \(line(skill.description))\n")
    }
  }

  static func joiningError(_ message: String, remedy: String) -> String {
    func sentence(_ text: String, capitalize: Bool) -> String {
      var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
      if capitalize, let first = text.first {
        text = first.uppercased() + text.dropFirst()
      }
      if let last = text.last, !".!?。！？".contains(last) { text += "." }
      return text
    }
    return sentence(message, capitalize: false) + " " + sentence(remedy, capitalize: true)
  }

  static func installed(_ results: [InstallResult]) {
    for name in Set(results.map(\.skill)).sorted() {
      let installs = results.filter { $0.skill == name }
      let modes = Set(installs.map { $0.mode.rawValue }).sorted()
      let recipients = installs.sorted { $0.agent.rawValue < $1.agent.rawValue }.map {
        $0.agent.rawValue + (modes.count > 1 ? " (\($0.mode.rawValue))" : "")
      }.joined(separator: ", ")
      let mode = modes.count == 1 ? " (\(modes[0]))" : ""
      write("Installed \(line(name)) for \(recipients)\(mode).\n")
    }
  }

  static func skillItems(_ results: [UpdateResult]) -> [HumanItem] {
    results.filter(\.changed).map { result in
      let live =
        result.oldHash == nil && result.newHash == nil
        && result.oldRevision == nil && result.newRevision == nil
      return HumanItem(
        name: result.skill, source: result.sourceIdentity,
        existed: result.oldHash != nil || result.oldRevision != nil
          || (live && (result.changes.isEmpty || result.changes.contains { $0.before != nil })),
        exists: result.newHash != nil || result.newRevision != nil
          || (live && (result.changes.isEmpty || result.changes.contains { $0.after != nil })),
        oldRevision: result.oldRevision, newRevision: result.newRevision,
        sameContent: result.oldHash != nil && result.oldHash == result.newHash,
        otherChanges: result.changes.contains {
          if case .symbolicLink = $0.before, case .symbolicLink = $0.after { return false }
          return true
        })
    }
  }

  static func differences(
    _ results: [UpdateResult], previous: SkillOutputInventory, paths: HumanPaths = HumanPaths()
  ) {
    let items = HumanItem.ordered(skillItems(results))
    if items.isEmpty { write("No skill changes.\n") }
    for item in items {
      write(item.render(paths: paths))
      for result in results where result.skill == item.name && result.sourceIdentity == item.source
      {
        skillFileDifferences(result, previous: previous, paths: paths)
      }
    }
  }

  static func availableInstructions(_ sections: [InstructionUnit]) {
    if sections.isEmpty { write("No instruction sections found in source.\n") }
    for unit in sections {
      write("\(line(unit.record.name))  \(line(unit.section.heading))\n")
    }
  }

  static func managedInstructions(_ report: InstructionListReport, paths: HumanPaths) {
    if report.sections.isEmpty && report.targets.isEmpty && report.prompts.isEmpty {
      write("No managed \(report.scope) instructions.\n")
    }
    for section in report.sections {
      write(
        "\(line(section.name))  \(paths.source(section.source))  \(line(HumanItem.pin(revision: section.revision, version: section.version)))\n"
      )
    }
    for target in report.targets {
      write("Target \(paths.path(target.target))  \(target.agents.joined(separator: ", "))\n")
    }
    for prompt in report.prompts {
      write(
        "ChatGPT \(line(prompt.name))  \(prompt.sections.map { line($0.name) }.joined(separator: ", "))\n"
      )
    }
  }

  static func instructionItems(_ report: InstructionUpdateReport) -> [HumanItem] {
    report.sections.map { section in
      HumanItem(
        name: section.after?.name ?? section.before?.name ?? "", instructions: true,
        source: section.after?.source ?? section.before?.source ?? "",
        existed: section.before != nil, exists: section.after != nil,
        oldRevision: section.before?.revision, newRevision: section.after?.revision,
        oldVersion: section.before?.version, newVersion: section.after?.version,
        sameContent: section.before?.hash == section.after?.hash,
        otherChanges: section.before?.source != section.after?.source
          || section.before?.path != section.after?.path)
    }
  }

  static func updateDifferences(
    skills: [UpdateResult], previous: SkillOutputInventory, instructions: InstructionUpdateReport,
    paths: HumanPaths
  ) {
    let items = HumanItem.ordered(skillItems(skills) + instructionItems(instructions))
    for item in items { write(item.render(paths: paths)) }
    if !skills.contains(where: \.changed) { write("No skill changes.\n") }
    for item in items where !item.instructions {
      if let result = skills.first(where: {
        $0.skill == item.name && $0.sourceIdentity == item.source
      }) {
        skillFileDifferences(result, previous: previous, paths: paths)
      }
    }
    if !instructions.hasChanges { write("No instruction changes.\n") }
    instructionTargets(instructions.targets, paths: paths)
    for prompt in instructions.changedPrompts { write("Changed ChatGPT prompt \(line(prompt)).\n") }
  }

  static func instructionDifferences(
    _ report: InstructionUpdateReport, paths: HumanPaths = HumanPaths()
  ) {
    if !report.hasChanges { write("No instruction changes.\n") }
    for item in HumanItem.ordered(instructionItems(report)) { write(item.render(paths: paths)) }
    instructionTargets(report.targets, paths: paths)
    for prompt in report.changedPrompts { write("Changed ChatGPT prompt \(line(prompt)).\n") }
  }

  static func instructionTargets(_ targets: [InstructionTargetChange], paths: HumanPaths) {
    for target in targets {
      let path = paths.path(target.url.path)
      for section in target.assembly.adoptedSections {
        write("Adopt \(line(section)) in \(path)\n")
      }
      for conflict in target.assembly.conflicts {
        write("Conflict \(line(conflict.sectionID)) in \(path)\n")
      }
      if target.agentsChanged {
        write(
          "Recipients of \(path): \(recipients(target.beforeAgents ?? [])) -> \(recipients(target.afterAgents))\n"
        )
      }
      if target.changed {
        write(
          "\(path) (\(recipients(target.afterAgents.isEmpty ? target.beforeAgents ?? [] : target.afterAgents)))\n"
        )
        fileDifference(
          path: target.url.path, before: target.before.map { .file($0) },
          after: target.after.map { .file($0) }, paths: paths)
      }
    }
  }

  static func recipients(_ agents: [AgentID]) -> String {
    agents.isEmpty ? "none" : agents.map(\.rawValue).sorted().joined(separator: ", ")
  }

  static func updatedInstructions(_ report: InstructionUpdateReport, paths: HumanPaths) {
    for target in report.targets where target.changed {
      write("Updated \(paths.path(target.url.path)).\n")
    }
  }

  static func promptReminder(_ prompts: [String]) {
    if prompts.isEmpty { return }
    write("Re-paste changed ChatGPT prompts (removed prompts must be cleared):\n")
    for prompt in prompts {
      write(
        "  \(line(prompt)) — render with 'agents instructions render chatgpt <prompt>' in the same scope.\n"
      )
    }
  }

}
