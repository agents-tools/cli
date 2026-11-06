import AgentsCore
import AgentsManifest
import ArgumentParser
import Foundation

struct Manifest: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "manifest", abstract: "Inspect the scope's Agents.swift declaration.",
    subcommands: [DumpManifest.self])
}

struct DumpManifest: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "dump", abstract: "Print the local manifest's evaluated JSON and source locations."
  )

  @OptionGroup var location: ScopeOptions
  @Flag(help: "Print the manifest language JSON contract.") var json = false

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
