import AgentsCore
import AgentsInstructions
import AgentsSkills
import Foundation

func withRecovery<T>(
  report: (String) -> Void = Terminal.notice,
  _ operation: () throws -> T
) throws -> T {
  do {
    return try operation()
  } catch CoreError.transactionRecovered(let path) {
    report("Recovered interrupted transaction at \(path); retrying once.")
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

  static func failureMessage(_ error: Error) -> String {
    let action: String
    switch error {
    case CoreError.transactionRecovered:
      action = "retry the command after other writers finish"
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
      action = "inspect the differences and use --replace to replace conflicting sections"
    case InstructionError.emptyPrompt:
      action =
        "declare the ChatGPT prompt in agents.json and run 'agents instructions update --apply'"
    case is InstructionError:
      action = "check the instruction source and target Markdown with 'agents doctor'"
    default:
      action = "check the command arguments and filesystem permissions"
    }
    return "\(error); \(action)."
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
    for result in results.sorted(by: {
      ($0.skill, $0.agent.rawValue) < ($1.skill, $1.agent.rawValue)
    }) {
      write(
        "Installed \(line(result.skill)) for \(result.agent.rawValue) (\(result.mode.rawValue)).\n")
    }
  }

  static func differences(_ results: [UpdateResult]) {
    let changed = results.filter(\.changed)
    if changed.isEmpty { write("No skill changes.\n") }
    for result in changed {
      write("Changed \(line(result.skill))\n")
      write(
        "  revision: \(line(result.oldRevision ?? "none")) -> \(line(result.newRevision ?? "none"))\n"
      )
      write("  hash: \(line(result.oldHash ?? "none")) -> \(line(result.newHash ?? "none"))\n")
      for change in result.changes {
        write("--- before/\(line(change.path))\n+++ after/\(line(change.path))\n")
        snapshot(change.before, prefix: "-")
        snapshot(change.after, prefix: "+")
      }
    }
  }

  static func availableInstructions(_ sections: [InstructionUnit]) {
    if sections.isEmpty { write("No instruction sections found in source.\n") }
    for unit in sections {
      write("\(line(unit.record.name))  \(line(unit.section.heading))\n")
    }
  }

  static func managedInstructions(_ report: InstructionListReport) {
    if report.sections.isEmpty && report.targets.isEmpty && report.prompts.isEmpty {
      write("No managed \(report.scope) instructions.\n")
    }
    for section in report.sections {
      write("\(line(section.name))  \(line(section.source))  \(line(section.revision ?? "none"))\n")
    }
    for target in report.targets {
      write("Target \(line(target.target))  \(target.agents.joined(separator: ", "))\n")
    }
    for prompt in report.prompts {
      write(
        "ChatGPT \(line(prompt.name))  \(prompt.sections.map { line($0.name) }.joined(separator: ", "))\n"
      )
    }
  }

  static func instructionDifferences(_ report: InstructionUpdateReport) {
    if !InstructionChanges.hasChanges(report) { write("No instruction changes.\n") }
    if report.lockMissing
      && (!report.sections.isEmpty || !report.targets.isEmpty || !report.changedPrompts.isEmpty)
    {
      write("Instruction lock is missing; applying will record resolved content.\n")
    }
    for section in report.sections {
      let name = section.after?.name ?? section.before?.name ?? ""
      let source = section.after?.source ?? section.before?.source ?? ""
      write("Changed instruction \(line(name))  \(line(source))\n")
      write(
        "  revision: \(line(section.before?.revision ?? "none")) -> \(line(section.after?.revision ?? "none"))\n"
      )
      write(
        "  hash: \(line(section.before?.hash ?? "none")) -> \(line(section.after?.hash ?? "none"))\n"
      )
    }
    for target in report.targets {
      for section in target.assembly.adoptedSections {
        write("Adopt \(line(section)) in \(line(target.url.path))\n")
      }
      for conflict in target.assembly.conflicts {
        write("Conflict \(line(conflict.sectionID)) in \(line(target.url.path))\n")
      }
      if target.changed {
        write("--- before/\(line(target.url.path))\n+++ after/\(line(target.url.path))\n")
        snapshot(target.before.map(SkillFileEntry.file), prefix: "-")
        snapshot(target.after.map(SkillFileEntry.file), prefix: "+")
      }
    }
    for prompt in report.changedPrompts { write("Changed ChatGPT prompt \(line(prompt)).\n") }
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

  private static func snapshot(_ entry: SkillFileEntry?, prefix: String) {
    switch entry {
    case nil: write("\(prefix) [absent]\n")
    case .directory: write("\(prefix) [directory]\n")
    case .symbolicLink(let destination): write("\(prefix) [symlink -> \(line(destination))]\n")
    case .file(let data):
      if let text = String(data: data, encoding: .utf8), !data.contains(0) {
        for textLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
          write("\(prefix)\(line(String(textLine)))\n")
        }
        if !text.hasSuffix("\n") { write("\\ No newline at end of file\n") }
      } else {
        write(
          "\(prefix) [binary file, \(data.count) bytes; base64: \(data.base64EncodedString())]\n")
      }
    }
  }
}
