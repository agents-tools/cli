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
    subcommands: [Skills.self, InstructionsCommand.self, Install.self, Update.self, Doctor.self]
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
      let options = arguments.prefix { $0 != "--" }
      if options.contains("--version"), options.contains(where: { !$0.hasPrefix("-") }) {
        throw ValidationError("--version is only available on 'agents'")
      }
      try validateHelpPath(arguments)
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

  private static func validateHelpPath(_ arguments: [String]) throws {
    var parent: any ParsableCommand.Type = Agents.self
    var isHelp = false
    for name in arguments {
      if name.hasPrefix("-") { return }
      if name == "help", !isHelp, !parent.configuration.subcommands.isEmpty {
        isHelp = true
        continue
      }
      guard
        let child = parent.configuration.subcommands.first(where: {
          $0.configuration.commandName == name
        })
      else {
        if !isHelp { return }
        throw ValidationError("Unknown command '\(name)'")
      }
      parent = child
    }
  }
}
