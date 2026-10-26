import AgentsCore
import AgentsInstructions
import AgentsSkills
import AgentsUpdates
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

  static func error(_ message: String, remedy: String) {
    FileHandle.standardError.write(Data(formatError(message, remedy: remedy).utf8))
  }

  static func formatError(_ message: String, remedy: String) -> String {
    func punctuate(_ text: String) -> String {
      var text = text
      if let last = text.lastIndex(where: { !" \t\r".contains($0) }),
        !".!?。！？".contains(text[last])
      {
        text.insert(".", at: text.index(after: last))
      }
      return text
    }
    var lines = message.components(separatedBy: "\n")
    while let last = lines.last, last.allSatisfy({ " \t\r".contains($0) }) {
      lines.removeLast()
    }
    if !lines.isEmpty { lines[lines.count - 1] = punctuate(lines[lines.count - 1]) }
    let error = lines.enumerated().map { index, text in
      (index == 0 ? "Error: " : "  ") + line(text)
    }.joined(separator: "\n")
    var remedy = remedy.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n"))
    if let first = remedy.first { remedy = first.uppercased() + remedy.dropFirst() }
    return (error.isEmpty ? "Error:" : error) + "\n  " + line(punctuate(remedy)) + "\n"
  }

  static func line(_ text: String) -> String {
    text.unicodeScalars.map { scalar in
      switch scalar {
      case "\t": return "\t"
      case "\n": return "\\n"
      case "\r": return "\\r"
      default:
        guard CharacterSet.controlCharacters.contains(scalar) else { return String(scalar) }
        let hex = String(scalar.value, radix: 16)
        return scalar.value <= 0xff
          ? "\\x" + String(repeating: "0", count: 2 - hex.count) + hex
          : "\\u{" + hex + "}"
      }
    }.joined()
  }

  static func text(_ text: String) -> String {
    text.components(separatedBy: "\n").map(line).joined(separator: "\n")
  }

  static func failureRemedy(_ error: Error, command: any ParsableCommand) -> String {
    if let error = error as? UpdateApplyError {
      return updateFailureRemedy(
        error.disposition, underlyingError: error.underlyingError, command: command)
    }
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
    case let error as GitError:
      switch error.operation {
      case .resolveRevision:
        action = "provide a Git revision that resolves to a commit in the watched source"
      default:
        action = "check Git access and the source location"
      }
    case CoreError.invalidSource, CoreError.notFound:
      action = "check the source, names, and paths"
    case CoreError.unsafePath:
      action = "use a path within the source directory"
    case CoreError.invalidSkill:
      action = "check SKILL.md and existing installations with 'agents doctor'"
    case CoreError.invalidState:
      action = "check the scope's agents.json, agents.resolved, and recovery journal"
    case CoreError.commandFailed:
      action = "check the command arguments and filesystem permissions"
    case InstructionError.unownedTargets:
      if command is AddInstructions || command is UpdateInstructions {
        action =
          "move what those files need into instructions files, then rerun with --replace to take them over"
      } else if command is Install || command is RemoveInstructions {
        action = "move what those files need into instructions files, delete them, and retry"
      } else {
        action =
          "move what those files need into instructions files, then run 'agents instructions update --apply --replace'"
      }
    case InstructionError.invalidLockedBlock:
      action =
        "run 'agents instructions update --apply' to regenerate the targets, adding --replace to take over files that agents did not generate"
    case InstructionError.ownChanged:
      action = "run 'agents instructions update --apply' to regenerate targets from the edited file"
    case InstructionError.invalidLinks:
      action =
        "link only to files in the checkout being written, or name the file in text without a link"
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
    return action
  }

  static func failureMessage(_ error: Error) -> String {
    guard let error = error as? UpdateApplyError else { return String(describing: error) }
    return updateFailureMessage(error.disposition, underlyingError: error.underlyingError)
  }

  static func updateFailureMessage(_ disposition: UpdateApplyDisposition, underlyingError: Error)
    -> String
  {
    let outcome: String
    switch disposition {
    case .unchanged: outcome = "Update failed; no update was applied."
    case .committed: outcome = "Update committed, but a later step failed."
    case .recoveryRequired: outcome = "Update failed; recovery is required."
    }
    return outcome + "\n" + String(describing: underlyingError)
  }

  static func updateFailureRemedy(
    _ disposition: UpdateApplyDisposition, underlyingError: Error, command: any ParsableCommand
  ) -> String {
    switch disposition {
    case .unchanged:
      return failureRemedy(underlyingError, command: command)
    case .committed:
      return "run 'agents doctor' in the same scope to inspect the committed update before retrying"
    case .recoveryRequired:
      return "run 'agents update --apply' in the same scope to recover and prepare a fresh update"
    }
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
      return HumanItem(
        name: result.skill, source: result.sourceIdentity,
        existed: result.membership.contains { $0.before != .absent },
        exists: result.membership.contains { $0.after != .absent },
        oldRevision: result.oldRevision, newRevision: result.newRevision,
        oldVersion: result.oldVersion, newVersion: result.newVersion,
        sameContent: result.oldHash != nil && result.oldHash == result.newHash,
        otherChanges: result.membership.contains { $0.before != $0.after }
          || result.changes.contains {
            if case .symbolicLink = $0.before, case .symbolicLink = $0.after { return false }
            return true
          })
    }
  }

  static func differences(
    _ results: [UpdateResult], paths: HumanPaths = HumanPaths()
  ) {
    let items = HumanItem.ordered(skillItems(results))
    missingSkillLock(results.contains(where: \.lockMissing))
    if items.isEmpty { write("No skill changes.\n") }
    for item in items {
      write(item.render(paths: paths))
      for result in results where result.skill == item.name && result.sourceIdentity == item.source
      {
        skillMembership(result, paths: paths)
        skillFileDifferences(result, paths: paths)
      }
    }
  }

  static func availableInstructions(_ sections: [InstructionUnit]) {
    if sections.isEmpty { write("No instruction sections found in source.\n") }
    for unit in sections {
      write(
        "\(line(unit.record.name))  \(line(unit.section.heading))  \(line(unit.section.description))\n"
      )
    }
  }

  static func instructionMappings(_ mappings: [InstructionMapping], paths: HumanPaths) {
    for mapping in mappings {
      let status: String
      switch mapping.status {
      case .locked: status = ""
      case .missingLock: status = "  no lock"
      case .pendingRecovery: status = "  recovery pending"
      case .unavailable(let reason): status = "  unavailable: " + line(reason)
      }
      let root = HumanPaths(scope: mapping.scope, environment: paths.environment)
        .path(mapping.root.path)
      write("\(root) (\(mapping.scope.rawValue))\(status)\n")
      for target in mapping.targets {
        let imported = target.import.map { "  imports " + line($0) } ?? ""
        write(
          "  \(paths.path(target.target))  \(recipients(target.agents))\(imported)\n")
        for section in target.sections { write(mappedSection(section, paths: paths)) }
      }
      if !mapping.unplaced.isEmpty { write("  Unplaced\n") }
      for section in mapping.unplaced { write(mappedSection(section, paths: paths)) }
      for (name, sections) in mapping.prompts.sorted(by: { $0.key < $1.key }) {
        write("  ChatGPT \(line(name))\n")
        for section in sections { write(mappedSection(section, paths: paths)) }
      }
    }
  }

  private static func mappedSection(_ section: LockedSection, paths: HumanPaths) -> String {
    let pinned = section.revision != nil || section.version != nil
    let pin =
      pinned ? "  " + line(HumanItem.pin(revision: section.revision, version: section.version)) : ""
    return "    \(line(section.name))  \(paths.source(section.source))\(pin)\n"
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
    _ report: CombinedUpdateReport, paths: HumanPaths
  ) {
    if !report.hasChanges {
      write("No changes.\n")
      return
    }
    let skills = report.skills
    let instructions = report.instructions
    missingSkillLock(report.lockMissing && !skills.isEmpty)
    let items = HumanItem.ordered(skillItems(skills) + instructionItems(instructions))
    for item in items {
      write(item.render(paths: paths))
      if !item.instructions, let result = skills.first(where: { $0.skill == item.name }) {
        skillMembership(result, paths: paths)
      }
    }
    for item in items where !item.instructions {
      if let result = skills.first(where: {
        $0.skill == item.name && $0.sourceIdentity == item.source
      }) {
        skillFileDifferences(result, paths: paths)
      }
    }
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
      if target.foreign { write("Take over \(path), which agents did not generate\n") }
      if target.agentsChanged {
        write(
          "Recipients of \(path): \(recipients(target.beforeAgents ?? [])) -> \(recipients(target.afterAgents))\n"
        )
      }
      if !target.changed, target.after != nil, target.afterAgents.isEmpty {
        write("Left \(path) in place because it differs from its generated version\n")
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
