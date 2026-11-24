import AgentsCore
import AgentsUpdates
import ArgumentParser
import Foundation

struct ImportCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "import",
    abstract:
      "Preview an explicit producer document; use --apply to merge and deploy canonical intent.")
  @Argument(help: "Document path relative to --root.") var document: String
  @Option(help: "Core import profile, for example codexConfigV1 or claudeCommandV1.") var format:
    String
  @Option(help: "Directory containing the producer document. Default: current directory.") var root:
    String = "."
  @Option(
    name: .long,
    help:
      "Select a producer member. Repeat for several; interpretation belongs to the import profile.")
  var select: [String] = []
  @OptionGroup var writing: ComponentWriteOptions
  @OptionGroup var options: UpdateOptions

  func run() throws {
    let environment = RuntimeEnvironment()
    let directory = URL(fileURLWithPath: root, relativeTo: environment.projectDirectory)
      .standardizedFileURL
    let imported = try SourceImportOperations.inspect(
      format: format, root: directory,
      document: document, selection: select.isEmpty ? nil : Set(select))
    if options.apply {
      let result = try withRecovery {
        let inspection = try UpdateOperations.inspect(scope: options.location.scope)
        try requireCommittedInspection(inspection)
        let request = try imported.updateRequest(in: inspection)
        return try UpdateOperations.withPreparedUpdate(
          writing.request(request), scope: options.location.scope,
          bindingProvider: writing.bindings.provider()
        ) { update in
          Terminal.updateDifferences(update.report, paths: options.location.paths)
          return try update.apply()
        }
      }
      Terminal.componentChanges(
        result.report.components, paths: options.location.paths, applied: true)
      Terminal.updatedSkills(result.report.skills)
      Terminal.updatedInstructions(result.report.instructions, paths: options.location.paths)
    } else {
      let report = ImportReport(imported)
      if options.json {
        try Terminal.json(report)
      } else {
        Terminal.write(
          "Import \(Terminal.line(report.format)): \(report.sources.count) sources, \(report.components.count) components.\n"
        )
        for diagnostic in report.diagnostics {
          Terminal.write(
            "  \(Terminal.line(diagnostic.code)) \(Terminal.line(diagnostic.document))\(Terminal.line(diagnostic.pointer)): \(Terminal.line(diagnostic.message))\n"
          )
        }
        for binding in report.bindings {
          Terminal.write(
            "  Required binding at \(Terminal.line(binding.document))\(Terminal.line(binding.pointer)): \(Terminal.line(binding.reason))\n"
          )
        }
        Terminal.write("Preview only. Run again with --apply to import.\n")
      }
    }
  }
}

struct ImportReport: Encodable {
  let schemaVersion = 1
  let kind = "import"
  let format: String
  let producerRevision: String?
  let specificationStatus: String
  let sources: [Source]
  let components: [Component]
  let diagnostics: [Diagnostic]
  let bindings: [Binding]
  let resources: [Resource]

  struct Source: Encodable {
    let alias: String
    let document: String
    let pointer: String
    let commit: String?
    let version: String?
    let developmentOnly: Bool
  }
  struct Component: Encodable {
    let document: String
    let pointer: String
    let kind: String
  }
  struct Diagnostic: Encodable {
    let code: String
    let document: String
    let pointer: String
    let message: String
  }
  struct Binding: Encodable {
    let document: String
    let pointer: String
    let reason: String
    let environmentVariable: String?
  }
  struct Resource: Encodable {
    let source: String
    let path: String?
    let hash: String?
    let selected: Bool
    let requiresStandaloneSource: Bool
  }

  init(_ inspection: SourceImportInspection) {
    format = inspection.format
    producerRevision = inspection.producerRevision
    specificationStatus = inspection.specificationStatus
    sources = inspection.sources.map {
      .init(
        alias: $0.alias, document: $0.document, pointer: $0.pointer,
        commit: $0.commit, version: $0.version, developmentOnly: $0.developmentOnly)
    }
    components = inspection.components.map {
      .init(document: $0.document, pointer: $0.pointer, kind: $0.declaration.kind.rawValue)
    }
    diagnostics = inspection.diagnostics.map {
      .init(code: $0.code, document: $0.document, pointer: $0.pointer, message: $0.message)
    }
    bindings = inspection.bindings.map {
      .init(
        document: $0.document, pointer: $0.pointer, reason: $0.reason,
        environmentVariable: $0.environmentVariable)
    }
    resources = inspection.resources.map {
      .init(
        source: $0.sourceAlias, path: $0.path, hash: $0.hash,
        selected: $0.selected, requiresStandaloneSource: $0.requiresStandaloneSource)
    }
  }
}
