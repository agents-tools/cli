import AgentsCore
import AgentsInstructions
import ArgumentParser
import Foundation

struct InstructionsCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "instructions",
    abstract: "Add, inspect, render, and maintain instructions.",
    subcommands: [
      AddInstructions.self, ListInstructions.self, RemoveInstructions.self,
      UpdateInstructions.self, RenderInstructions.self, InitializeInstructions.self,
    ])
}

struct InstructionAgentOptions: ParsableArguments {
  @Option(
    name: .long,
    help:
      "Set recipients of the scope's section list: codex, claude-code, cursor, gemini-cli or opencode. Repeat for several. Default: the recorded instruction agents, else the declaration's agents, else codex and claude-code.",
    transform: AgentID.parse)
  var agent: [AgentID] = []

  var recipients: [AgentID]? {
    agent.isEmpty ? nil : Array(Set(agent)).sorted { $0.rawValue < $1.rawValue }
  }
}

struct AddInstructions: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "add", abstract: "Declare and install instruction sections from a source.")

  @Argument(help: "Git URL, local Git directory, or declared source alias.") var source: String
  @Argument(
    help:
      "Sections to add in order. Omit to add the source's only section, or to list the choices when it has several."
  )
  var names: [String] = []
  @OptionGroup var location: ScopeOptions
  @OptionGroup var agents: InstructionAgentOptions
  @OptionGroup var discovery: SourcePathOptions
  @OptionGroup var requirements: RequirementOptions
  @Flag(help: "Show differences, then replace conflicting custom sections.") var replace = false

  func run() throws {
    let outcome = try withRecovery {
      try InstructionOperations.add(
        InstructionAddOptions(
          source: source, names: names, replace: replace, agents: agents.recipients,
          scope: location.scope, path: discovery.path, sourceRequirement: requirements.requirement),
        beforeApply: {
          Terminal.instructionTargets(
            $0.targets.filter { !$0.assembly.conflicts.isEmpty }, paths: location.paths)
        })
    }
    if outcome.result == nil {
      Terminal.availableInstructions(outcome.available)
      Terminal.write("Select names with 'agents instructions add <source> <names...>'.\n")
    } else if let result = outcome.result {
      let selected = names.isEmpty ? outcome.available.map { $0.record.name } : names
      let locked = try InstructionOperations.listManaged(scope: location.scope)
      for target in result.targets
      where !target.afterAgents.isEmpty && locked.targets[target.target]?.import == nil {
        Terminal.write(
          "Added \(selected.map(Terminal.line).joined(separator: ", ")) to \(location.paths.path(target.url.path)) (\(Terminal.recipients(target.afterAgents))).\n"
        )
      }
    }
  }
}

struct ListInstructions: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: "List managed sections and targets, or discover sections in a source.")

  @Argument(help: "Inspect this source instead of managed instructions.") var source: String?
  @OptionGroup var location: ScopeOptions
  @OptionGroup var discovery: SourcePathOptions
  @Flag(help: "Print the versioned JSON report.") var json = false

  func validate() throws {
    if source == nil && discovery.path != nil {
      throw ValidationError("--path requires a source argument")
    }
  }

  func run() throws {
    if let source {
      let outcome = try withRecovery {
        try InstructionOperations.add(
          InstructionAddOptions(
            source: source, listOnly: true, scope: location.scope, path: discovery.path))
      }
      if json {
        try Terminal.json(InstructionSourceReport(scope: location.scope.rawValue, outcome: outcome))
      } else {
        Terminal.availableInstructions(outcome.available)
      }
    } else {
      let locked = try withRecovery {
        try InstructionOperations.listManaged(scope: location.scope)
      }
      let report = InstructionListReport(scope: location.scope.rawValue, locked: locked)
      if json {
        try Terminal.json(report)
      } else {
        Terminal.managedInstructions(report, paths: location.paths)
      }
    }
  }
}

struct RemoveInstructions: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "remove", abstract: "Remove declared sections from instruction files and prompts.")

  @Argument(help: "Section names, or source-alias:name when a name is ambiguous.") var names:
    [String]
  @OptionGroup var location: ScopeOptions
  @OptionGroup var agents: InstructionAgentOptions

  func validate() throws {
    if names.isEmpty { throw ValidationError("Specify at least one instruction section name") }
  }

  func run() throws {
    let result = try withRecovery {
      try InstructionOperations.remove(
        names: names, scope: location.scope, agents: agents.recipients,
        beforeApply: { Terminal.instructionTargets($0.targets, paths: location.paths) })
    }
    for target in result.targets where target.changed {
      Terminal.write(
        "Removed \(names.map(Terminal.line).joined(separator: ", ")) from \(location.paths.path(target.url.path)).\n"
      )
    }
    Terminal.promptReminder(result.changedPrompts)
  }
}

struct UpdateInstructions: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "update", abstract: "Preview or apply updates to all declared instructions.")

  @OptionGroup var options: UpdateOptions
  @OptionGroup var agents: InstructionAgentOptions

  func run() throws {
    let result = try options.updateInstructions(agents: agents.recipients)
    if options.json {
      try Terminal.json(
        InstructionPreviewReport(
          scope: options.location.scope.rawValue, instructions: InstructionChanges(result)))
    } else {
      options.finishInstructions(result)
    }
  }
}

struct RenderInstructions: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "render", abstract: "Print a ChatGPT prompt from the locked sections.",
    subcommands: [RenderChatGPT.self])
}

struct RenderChatGPT: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "chatgpt", abstract: "Print a locked ChatGPT prompt for pasting, without markers.")

  @Argument(help: "Name of a ChatGPT prompt in the scope's declaration and lock.") var prompt:
    String
  @OptionGroup var location: ScopeOptions

  func run() throws {
    let bytes = try withRecovery {
      _ = try InstructionOperations.listManaged(scope: location.scope)
      let declarationURL = StateStore(scope: location.scope, environment: RuntimeEnvironment())
        .declarationURL
      let declaration: Declaration
      do {
        declaration = try JSONDecoder().decode(
          Declaration.self, from: Data(contentsOf: declarationURL))
      } catch CocoaError.fileReadNoSuchFile {
        declaration = Declaration()
      }
      guard declaration.instructions?.chatgpt?[prompt] != nil else {
        throw HumanOutputError.undeclaredPrompt(prompt)
      }
      return try InstructionOperations.renderChatGPT(prompt: prompt, scope: location.scope)
    }
    FileHandle.standardOutput.write(bytes)
  }
}

struct InitializeInstructions: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "init",
    abstract: "Create a named instructions Markdown file in the current directory.")

  @Argument(help: "New instruction file name, without the .md extension.") var name: String

  func run() throws {
    let file = try withRecovery {
      try InstructionOperations.initializeInstructions(
        named: name, directory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    }
    Terminal.write("Created \(HumanPaths().path(file.path)).\n")
  }
}

enum HumanOutputError: Error, CustomStringConvertible {
  case undeclaredPrompt(String)

  var description: String {
    switch self {
    case .undeclaredPrompt(let name): "No ChatGPT prompt named '\(name)' is declared."
    }
  }
}
