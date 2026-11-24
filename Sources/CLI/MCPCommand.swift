import AgentsCore
import AgentsUpdates
import ArgumentParser
import Foundation

struct MCPCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "mcp",
    abstract: "Explicitly test a managed MCP connection.", subcommands: [TestMCP.self])
}

struct TestMCP: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "test",
    abstract:
      "Initialize one exact managed MCP server and discover tools; may start its process or contact its endpoint."
  )
  @OptionGroup var selection: ComponentSelector
  @OptionGroup var location: ScopeOptions
  @OptionGroup var bindings: BindingOptions
  @Flag(help: "Print the versioned JSON result.") var json = false

  mutating func run() async throws {
    let environment = RuntimeEnvironment()
    let inspection = try UpdateOperations.inspect(scope: location.scope, environment: environment)
    let selected = try selection.select(in: inspection)
    guard
      inspection.components.contains(where: {
        $0.selection.identity == selected.identity && $0.kind == .mcpServer
      })
    else {
      throw CoreError.invalidState("select an MCP server component")
    }
    let snapshot = try MCPConnectionOperations.snapshot(
      selection: selected, scope: location.scope, environment: environment)
    let provider = try bindings.provider()
    for name in MCPConnectionOperations.describe(snapshot).requiredBindings
    where provider.variables[name] == nil {
      throw CoreError.invalidState("runtime binding unavailable: \(name)")
    }
    let result = await MCPConnectionOperations.test(
      snapshot, environment: environment, bindings: provider)
    let report = MCPTestReport(result)
    if json {
      try Terminal.json(report)
    } else {
      Terminal.write(
        "MCP \(Terminal.line(selection.name)): \(Terminal.line(report.outcome))\(report.issue.map { " (\(Terminal.line($0)))" } ?? "").\n"
      )
      for tool in report.tools { Terminal.write("  \(Terminal.line(tool.name))\n") }
    }
    guard result.outcome == .discovered || result.outcome == .noTools, result.cleanupComplete else {
      throw ExitCode.failure
    }
  }
}

struct MCPTestReport: Encodable {
  let schemaVersion = 1
  let kind = "mcp-test"
  let transport: String
  let outcome: String
  let issue: String?
  let negotiatedVersion: String?
  let cleanupComplete: Bool
  let elapsed: TimeInterval
  let tools: [Tool]
  struct Tool: Encodable {
    let name: String
    let title: String?
    let description: String?
  }

  init(_ result: MCPConnectionTestResult) {
    transport = result.transport.rawValue
    outcome = result.outcome.rawValue
    issue = result.issue?.rawValue
    negotiatedVersion = result.negotiatedVersion
    cleanupComplete = result.cleanupComplete
    elapsed = result.elapsed
    tools = result.tools.map { .init(name: $0.name, title: $0.title, description: $0.description) }
  }
}
