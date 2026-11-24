import AgentsCore
import AgentsUpdates
import ArgumentParser
import Foundation

struct BindingOptions: ParsableArguments {
  @Option(
    name: .long,
    help:
      "Supply a runtime binding from NAME=ENV_VAR. Repeat for several; values are read only when applying or testing."
  )
  var binding: [String] = []

  func validate() throws { _ = try provider() }

  func provider() throws -> EnvironmentBindings {
    guard binding.count <= 256 else { throw ValidationError("At most 256 bindings are supported") }
    var variables: [String: String] = [:]
    for mapping in binding {
      let parts = mapping.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
      guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty,
        mapping.utf8.count <= 4096,
        !mapping.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
        !parts[1].contains("="), variables[String(parts[0])] == nil
      else { throw ValidationError("Use distinct --binding NAME=ENV_VAR mappings") }
      variables[String(parts[0])] = String(parts[1])
    }
    return EnvironmentBindings(variables: variables)
  }
}

struct EnvironmentBindings: RuntimeBindingProvider {
  let variables: [String: String]

  func value(for binding: String, environment: RuntimeEnvironment) throws -> Data {
    guard let variable = variables[binding], let value = environment.environment[variable] else {
      throw CoreError.invalidState("runtime binding unavailable: \(binding)")
    }
    guard value.utf8.count <= 1_048_576, !value.utf8.contains(0) else {
      throw CoreError.invalidState("runtime binding invalid: \(binding)")
    }
    return Data(value.utf8)
  }
}

struct ComponentWriteOptions: ParsableArguments {
  @OptionGroup var bindings: BindingOptions
  @Flag(help: "Replace conflicting content where Core supports explicit takeover.") var replace =
    false
  @Flag(help: "Allow Core's reported owner-only permission change for private materialization.")
  var changingAccess = false

  func request(_ request: UpdateRequest = UpdateRequest()) -> UpdateRequest {
    var request = request
    request.replace = replace
    request.changingAccess = changingAccess
    return request
  }
}
