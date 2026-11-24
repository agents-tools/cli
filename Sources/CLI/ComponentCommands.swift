import AgentsCore
import AgentsUpdates
import ArgumentParser
import Foundation

struct ComponentsCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "components",
    abstract: "Inspect, add and remove managed components.",
    subcommands: [ListComponents.self, AddComponents.self, RemoveComponents.self])
}

/// Builds canonical group intent; source parsing and graph discovery remain in Core.
struct ComponentSourceOptions: ParsableArguments {
  @Option(help: "Group exported by the source.") var group: String?
  @Option(help: "Alias for a new source; existing aliases can be used directly.") var alias: String?
  @OptionGroup var requirements: RequirementOptions
  @OptionGroup var path: SourcePathOptions

  func validate() throws {
    if group?.isEmpty == true || alias?.isEmpty == true {
      throw ValidationError("Group and source alias must not be empty")
    }
  }

  func declaration(source: String, inspection: ScopeInspection) throws -> Declaration {
    guard var declaration = inspection.declaration, !inspection.recovery.pending else {
      throw CoreError.recoveryPending(
        inspection.recovery.diagnostic ?? "Transaction recovery is pending")
    }
    guard let group, !group.isEmpty else { throw ValidationError("A source requires --group") }
    let name: String
    if declaration.sources[source] != nil {
      guard alias == nil || alias == source else {
        throw ValidationError("Use the existing source alias directly")
      }
      name = source
      if let requirement = requirements.requirement {
        declaration.sources[name]?.requirement = requirement
      }
      if let path = path.path { declaration.sources[name]?.path = path }
    } else {
      guard let alias, !alias.isEmpty else {
        throw ValidationError("A new source requires --alias")
      }
      guard declaration.sources[alias] == nil else {
        throw ValidationError("Source alias already exists")
      }
      let environment = RuntimeEnvironment()
      let parsed = try SourceParser.parse(
        source, currentDirectory: environment.projectDirectory,
        homeDirectory: environment.homeDirectory)
      name = alias
      declaration.sources[name] = SourceDeclaration(
        kind: parsed.type, location: parsed.localPath ?? parsed.url,
        requirement: requirements.requirement ?? parsed.requirement,
        path: path.path ?? parsed.subpath)
    }
    let use = GroupUseDeclaration(name: group, source: name)
    if !declaration.uses.contains(use) { declaration.uses.append(use) }
    return declaration
  }
}

struct ListComponents: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "list",
    abstract: "Inspect managed components, or discover an exported source group without installing."
  )
  @Argument(help: "Source alias, local directory or repository URL to discover.") var source:
    String?
  @OptionGroup var selection: ComponentSourceOptions
  @OptionGroup var location: ScopeOptions
  @Flag(help: "Print the versioned JSON report.") var json = false

  func validate() throws {
    if source != nil && selection.group == nil {
      throw ValidationError("A source requires --group")
    }
    if source == nil
      && (selection.group != nil || selection.alias != nil || selection.path.path != nil
        || selection.requirements.requirement != nil)
    {
      throw ValidationError("Source options require a source argument")
    }
  }

  func run() throws {
    let inspection = try UpdateOperations.inspect(scope: location.scope)
    try requireCommittedInspection(inspection)
    let components: [ComponentInspection]
    if let source {
      components = try UpdateOperations.discover(
        selection.declaration(source: source, inspection: inspection), scope: location.scope
      ).components
    } else {
      components = inspection.components
    }
    if json {
      try Terminal.json(ComponentListReport(scope: location.scope, components: components))
    } else {
      Terminal.componentList(components)
    }
  }
}

struct AddComponents: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "add",
    abstract: "Declare and apply an exported source group.")
  @Argument(help: "Source alias, local directory or repository URL.") var source: String
  @OptionGroup var selection: ComponentSourceOptions
  @OptionGroup var location: ScopeOptions
  @OptionGroup var writing: ComponentWriteOptions

  func validate() throws {
    if selection.group == nil { throw ValidationError("Provide --group") }
  }

  func run() throws {
    let result = try withRecovery {
      let inspection = try UpdateOperations.inspect(scope: location.scope)
      try requireCommittedInspection(inspection)
      let discovered = try UpdateOperations.discover(
        selection.declaration(source: source, inspection: inspection), scope: location.scope)
      return try UpdateOperations.withPreparedUpdate(
        writing.request(discovered.updateRequest()), scope: location.scope,
        bindingProvider: writing.bindings.provider()
      ) { try $0.apply() }
    }
    Terminal.updatedSkills(result.report.skills)
    Terminal.updatedInstructions(result.report.instructions, paths: location.paths)
    Terminal.componentChanges(result.report.components, paths: location.paths, applied: true)
  }
}

struct ComponentSelector: ParsableArguments {
  @Argument(help: "Exact managed component name.") var name: String
  @Option(help: "Limit to a component kind.", transform: parseComponentKind) var kind:
    DeclaredComponentKind?
  @Option(help: "Exact logical identity from components list; disambiguates duplicate names.")
  var identity: String?
  @Option(help: "Exact occurrence ID from components list.") var occurrence: Int?

  func validate() throws {
    if let occurrence, occurrence < 0 {
      throw ValidationError("Occurrence IDs must be nonnegative")
    }
  }

  func select(in inspection: ScopeInspection) throws -> ComponentSelection {
    try requireCommittedInspection(inspection)
    let matches = inspection.components.filter {
      $0.name == name && (kind == nil || $0.kind == kind)
        && (identity == nil || $0.selection.identity == identity)
        && (occurrence == nil || $0.occurrences.contains { $0.selection.occurrence == occurrence })
    }
    guard matches.count == 1, let component = matches.first else {
      throw CoreError.invalidState(
        "component selection is missing or ambiguous; use components list and --kind/--identity")
    }
    guard let occurrence else { return component.selection }
    let occurrences = component.occurrences.filter { $0.selection.occurrence == occurrence }
    guard occurrences.count == 1, let selected = occurrences.first else {
      throw CoreError.invalidState(
        "component occurrence is missing or ambiguous; refresh components list")
    }
    return selected.selection
  }
}

func parseComponentKind(_ value: String) throws -> DeclaredComponentKind {
  guard let kind = DeclaredComponentKind(rawValue: value) else {
    throw ValidationError("Unknown component kind")
  }
  return kind
}

func requireCommittedInspection(_ inspection: ScopeInspection) throws {
  if inspection.recovery.pending {
    throw CoreError.recoveryPending(
      inspection.recovery.diagnostic ?? "Transaction recovery is pending")
  }
}

struct RemoveComponents: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "remove", abstract: "Remove an exact managed component or occurrence.")
  @OptionGroup var selection: ComponentSelector
  @OptionGroup var location: ScopeOptions
  @OptionGroup var agents: AgentOptions
  @OptionGroup var writing: ComponentWriteOptions

  func run() throws {
    let result = try withRecovery {
      let inspection = try UpdateOperations.inspect(scope: location.scope)
      let selected = try selection.select(in: inspection)
      let request = UpdateRequest(
        operation: .remove, selections: [selected], agents: agents.recipients)
      return try UpdateOperations.withPreparedUpdate(
        writing.request(request), scope: location.scope,
        bindingProvider: writing.bindings.provider()
      ) { try $0.apply() }
    }
    Terminal.updatedSkills(result.report.skills)
    Terminal.updatedInstructions(result.report.instructions, paths: location.paths)
    Terminal.componentChanges(result.report.components, paths: location.paths, applied: true)
  }
}
