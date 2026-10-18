import ArgumentParser
import Darwin
import Foundation

enum BuildInfo {
  static let version = "0.1.0"
}

struct Agents: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "agents",
    abstract: "Manage agent skills from declared sources.",
    version: "agents \(BuildInfo.version)",
    subcommands: [Skills.self, Install.self, Update.self, Doctor.self]
  )
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
      Terminal.error(Terminal.failureMessage(error))
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
