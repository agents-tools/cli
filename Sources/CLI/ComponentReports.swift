import AgentsCore
import AgentsUpdates
import Foundation

struct ComponentChangeItem: Encodable {
  let kind: String
  let name: String
  let source: String
  let revision: String?
  let version: String?
  let path: String
  let format: String
  let ownership: String
  let agents: [String]
  let changed: Bool
  let requiredBindings: [String]
  let effectiveReaders: [String]
  let privateMaterialization: Bool
  let before: String?
  let after: String?
  let resources: [Resource]
  let permissionChange: Permissions?

  struct Resource: Encodable {
    let path: String
    let hash: String
    let executableFiles: [String: Bool]
  }
  struct Permissions: Encodable {
    let beforeOwner: UInt32
    let beforeGroup: UInt32
    let beforeMode: UInt32
    let afterOwner: UInt32
    let afterMode: UInt32
    let ownerOnly: Bool
  }

  init(_ change: ComponentUpdateChange) {
    kind = change.kind
    name = change.name
    source = change.sourceIdentity
    revision = change.revision
    version = change.version
    path = change.path
    format = change.format
    ownership = change.ownership
    agents = change.agents.map(\.rawValue)
    changed = change.changed
    requiredBindings = change.requiredBindings
    effectiveReaders = change.effectiveReaders.map(\.rawValue)
    privateMaterialization = change.privateMaterialization
    before = change.symbolicBefore
    after = change.symbolicAfter
    resources = change.resources.map {
      .init(path: $0.path, hash: $0.hash, executableFiles: $0.executableFiles)
    }
    permissionChange = change.permissionChange.map {
      .init(
        beforeOwner: $0.beforeOwner, beforeGroup: $0.beforeGroup, beforeMode: $0.beforeMode,
        afterOwner: $0.afterOwner, afterMode: $0.afterMode, ownerOnly: $0.ownerOnly)
    }
  }
}

struct ComponentListReport: Encodable {
  let schemaVersion = 1
  let kind = "components"
  let scope: String
  let components: [Item]

  struct Item: Encodable {
    let identity: String
    let generation: String
    let kind: String
    let name: String
    let source: String
    let group: String?
    let revision: String?
    let agents: [String]
    let occurrences: [Occurrence]
  }
  struct Occurrence: Encodable {
    let id: Int?
    let source: String
    let manifestPath: String
    let consumerEditable: Bool
  }

  init(scope: InstallScope, components: [ComponentInspection]) {
    self.scope = scope.rawValue
    self.components = components.map {
      .init(
        identity: $0.selection.identity, generation: $0.selection.generation,
        kind: $0.kind.rawValue, name: $0.name, source: $0.source, group: $0.group,
        revision: $0.revision, agents: $0.recipients.map(\.rawValue),
        occurrences: $0.occurrences.map {
          .init(
            id: $0.selection.occurrence, source: $0.declaringSource,
            manifestPath: $0.manifestPath, consumerEditable: $0.consumerEditable)
        })
    }
  }
}

extension Terminal {
  static func componentChanges(
    _ components: [ComponentUpdateChange], paths: HumanPaths, applied: Bool
  ) {
    for component in components {
      let verb = applied ? "Applied" : component.changed ? "Change" : "Unchanged"
      write(
        "\(verb) \(line(component.kind)) \(line(component.name)) in \(paths.path(component.path)) (\(line(component.format))).\n"
      )
      if !applied {
        if let before = component.symbolicBefore { write("  Before: \(line(before))\n") }
        if let after = component.symbolicAfter { write("  After: \(line(after))\n") }
        if !component.requiredBindings.isEmpty {
          write(
            "  Required bindings: \(component.requiredBindings.map(line).joined(separator: ", "))\n"
          )
        }
        if let access = component.permissionChange {
          write(
            "  Permissions: \(String(access.beforeMode, radix: 8)) -> \(String(access.afterMode, radix: 8)); owner \(access.afterOwner).\n"
          )
        }
      }
    }
  }

  static func componentList(_ components: [ComponentInspection]) {
    if components.isEmpty { write("No components.\n") }
    for component in components {
      write("\(line(component.kind.rawValue)) \(line(component.name))  \(line(component.source))\n")
      write("  Identity: \(line(component.selection.identity))\n")
      for occurrence in component.occurrences {
        write(
          "  Occurrence \(occurrence.selection.occurrence.map(String.init) ?? "all"): \(line(occurrence.manifestPath))\n"
        )
      }
    }
  }
}
