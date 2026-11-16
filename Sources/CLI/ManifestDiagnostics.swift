import AgentsCore
import AgentsManifest
import Foundation

/// Editor diagnostics link to lines; Core columns measure UTF-8 bytes, not editor characters.
enum ManifestDiagnostics {
  static func write(_ diagnostics: [ManifestDiagnostic]) {
    let text = diagnostics.map(render).joined()
    FileHandle.standardError.write(Data(text.utf8))
  }

  static func render(_ diagnostic: ManifestDiagnostic) -> String {
    let primary = location(
      diagnostic.span, severity: diagnostic.severity.rawValue, code: diagnostic.code,
      message: diagnostic.message)
    let related = diagnostic.related.map {
      location($0, severity: "info", code: diagnostic.code, message: "related location")
    }.joined()
    return primary + related
  }

  private static func location(
    _ span: SourceSpan, severity: String, code: String, message: String
  ) -> String {
    let path = span.document.rawValue
    let visible = singleLine(path)
    // Escaped file names describe the original path, but are not clickable file identities.
    let prefix =
      visible == path && path.hasPrefix("/")
      ? "\(path):\(span.line): "
      : "Diagnostic at \(visible) (line \(span.line)): "
    return prefix + "\(severity) [\(singleLine(code))]: \(singleLine(message))"
      + " (UTF-8 byte column \(span.column))\n"
  }

  private static func singleLine(_ text: String) -> String {
    Terminal.line(text)
      .replacingOccurrences(of: "\t", with: "\\t")
      .replacingOccurrences(of: "\u{2028}", with: "\\u{2028}")
      .replacingOccurrences(of: "\u{2029}", with: "\\u{2029}")
  }
}
