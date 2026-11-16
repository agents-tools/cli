import AgentsCore
import AgentsManifest
import ArgumentParser
import Foundation

struct Manifest: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "manifest", abstract: "Inspect declarations and the bundled YAML schema.",
    subcommands: [DumpManifest.self, SchemaManifest.self, CheckManifest.self])
}

struct DumpManifest: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "dump", abstract: "Print the local manifest's JSON and source locations."
  )

  @OptionGroup var location: ScopeOptions
  @Flag(help: "Print the manifest JSON contract.") var json = false

  func validate() throws {
    if !json { throw ValidationError("manifest dump requires --json") }
  }

  func run() throws {
    let store = StateStore(scope: location.scope)
    guard let document = try store.loadManifest() else {
      throw CoreError.notFound("declaration at \(store.declarationURL.path)")
    }
    let bytes = try ManifestDump(document: document).encodedJSON()
    FileHandle.standardOutput.write(Data(bytes))
  }
}

struct SchemaManifest: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "schema", abstract: "Print the bundled manifest JSON schema.")

  func run() throws {
    FileHandle.standardOutput.write(Data(try ManifestSchemaResource.encodedJSON()))
  }
}

struct CheckManifest: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "check", abstract: "Check the saved declaration without resolving sources.")

  @OptionGroup var location: ScopeOptions

  func run() throws {
    let store = StateStore(scope: location.scope)
    do {
      guard let document = try store.loadManifest() else {
        throw CoreError.notFound("declaration at \(store.declarationURL.path)")
      }
      ManifestDiagnostics.write(document.diagnostics)
      if document.diagnostics.contains(where: { $0.severity == .error }) {
        throw ExitCode.failure
      }
    } catch let failure as ManifestFailure {
      ManifestDiagnostics.write(failure.diagnostics)
      throw ExitCode.failure
    }
  }
}
