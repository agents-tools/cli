import ArgumentParser
import Darwin
import Foundation

enum BuildInfo {
  static let version = "0.1.0"
}

struct Agents: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "agents",
    abstract: "Manage agent skills and instructions from declared sources.",
    discussion: """
      Examples:
        agents skills add github.com/owner/skills pdf-forms
        agents skills list
        agents instructions add <source> canonical-artifacts
        agents instructions render chatgpt <prompt> | pbcopy
        agents install
        agents update               Preview what re-resolving would change
        agents update --apply       Write the updates and the new lock
      """,
    subcommands: [
      Skills.self, InstructionsCommand.self, Watch.self, Install.self, Update.self, Doctor.self,
    ]
  )

  @Flag(help: "Show the version.") var version = false

  func run() throws {
    if version { throw CleanExit.message("agents \(BuildInfo.version)") }
    throw CleanExit.helpRequest(self)
  }
}

struct Skills: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "skills",
    abstract: "Add, inspect, restore, and maintain skills.",
    subcommands: [Add.self, ListSkills.self, Remove.self, UpdateSkills.self, Initialize.self]
  )
}

@main
enum EntryPoint {
  static func main() {
    var command: any ParsableCommand
    do {
      let arguments = Array(CommandLine.arguments.dropFirst())
      try validateCommandPath(arguments)
      let options = arguments.prefix { $0 != "--" }
      if options.contains("--version"), options.contains(where: { !$0.hasPrefix("-") }) {
        throw ValidationError("--version is only available on 'agents'")
      }
      command = try Agents.parseAsRoot(arguments)
    } catch {
      let code = Agents.exitCode(for: error)
      if code == .success {
        print(Agents.fullMessage(for: error))
        return
      }
      Terminal.error("\(Agents.message(for: error)); run 'agents --help' for usage.")
      Darwin.exit(64)
    }
    do {
      try command.run()
    } catch {
      // Help requests from a command group are successful parser exits.
      if Agents.exitCode(for: error) == .success {
        print(Agents.fullMessage(for: error))
        return
      }
      if let code = error as? ExitCode {
        Darwin.exit(code.rawValue)
      }
      Terminal.error(Terminal.failureMessage(error, command: command))
      Darwin.exit(1)
    }
  }

  private static func validateCommandPath(_ arguments: [String]) throws {
    var parent: any ParsableCommand.Type = Agents.self
    var isHelp = false
    var tokens = arguments.makeIterator()
    while let name = tokens.next() {
      if name == "--" { return }
      if name != "-", name.hasPrefix("-") {
        if name == "--help" || name == "-h" { continue }
        if !name.contains("="), try takesValue(name, command: parent) {
          if tokens.next() == "--" { return }
        }
        continue
      }
      if name == "help", !isHelp, !parent.configuration.subcommands.isEmpty {
        isHelp = true
        continue
      }
      guard
        let child = parent.configuration.subcommands.first(where: {
          $0.configuration.commandName == name
        })
      else {
        if !isHelp && parent.configuration.subcommands.isEmpty { return }
        throw ValidationError("Unknown command '\(name)'")
      }
      parent = child
    }
  }

  // `_dumpHelp()` is outside ArgumentParser's stability guarantee: revalidate the
  // unknown-command tests in ExecutableTests on every parser upgrade, including patches.
  private static func takesValue(_ name: String, command: any ParsableCommand.Type) throws -> Bool {
    let help = try JSONDecoder().decode(CommandHelp.self, from: Data(command._dumpHelp().utf8))
    if help.command.arguments.contains(where: { argument in
      argument.kind == "option"
        && argument.names?.contains {
          ($0.kind == "long" ? "--" : "-") + $0.name == name
        } == true
    }) {
      return true
    }
    if let defaultCommand = command.configuration.defaultSubcommand {
      return try takesValue(name, command: defaultCommand)
    }
    return false
  }
}

private struct CommandHelp: Decodable {
  let command: Definition

  struct Definition: Decodable {
    let arguments: [Argument]
  }

  struct Argument: Decodable {
    let kind: String
    let names: [Name]?
  }

  struct Name: Decodable {
    let kind: String
    let name: String
  }
}
