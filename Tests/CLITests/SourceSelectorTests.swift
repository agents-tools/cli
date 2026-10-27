import Foundation
import Testing

struct SourceSelectorTests {
  private func declaration(_ fixture: CLIFixture) throws -> [String: Any] {
    try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: fixture.state("agents.json")))
        as? [String: Any])
  }

  @Test func skillAddStoresSelectorsAsDeclarationFields() throws {
    let fixture = try CLIFixture()
    try fixture.skill("demo")
    try fixture.skill("other")
    try fixture.commit()
    try fixture.success([
      "skills", "add", fixture.source.path + "@branch:main@skill:demo", "--agent", "codex",
    ])
    let declaration = try declaration(fixture)
    let sources = try #require(declaration["sources"] as? [String: [String: String]])
    #expect(sources == ["source": ["local": fixture.source.path, "branch": "main"]])
    let skills = try #require(declaration["skills"] as? [String: [String: Any]])
    #expect(skills["source"]?["select"] as? [String] == ["demo"])
  }

  @Test func instructionAddAcceptsRequirementsAndRejectsSkillSelectors() throws {
    let fixture = try CLIFixture()
    let instructions = fixture.source.appendingPathComponent("instructions")
    try FileManager.default.createDirectory(at: instructions, withIntermediateDirectories: true)
    try Data("---\ndescription: Rules.\n---\n# Rules\n\nFollow them.\n".utf8).write(
      to: instructions.appendingPathComponent("rules.md"))
    try fixture.commit()
    let rejected = try fixture.run([
      "instructions", "add", fixture.source.path + "@skill:rules", "--agent", "codex",
    ])
    #expect(rejected.status == 1 && rejected.stderr.contains("@skill:"))
    try fixture.success([
      "instructions", "add", fixture.source.path + "@branch:main", "rules", "--agent", "codex",
    ])
    let sources = try #require(try declaration(fixture)["sources"] as? [String: [String: String]])
    #expect(sources["source"]?["branch"] == "main")
  }

  @Test func sourcesSharingALastComponentGetDistinctAliases() throws {
    let fixture = try CLIFixture()
    try fixture.skill("demo")
    try fixture.commit()
    let mirror = fixture.root.appendingPathComponent("mirror/source")
    try FileManager.default.createDirectory(
      at: mirror.deletingLastPathComponent(), withIntermediateDirectories: true)
    try fixture.git(["clone", "--quiet", fixture.source.path, mirror.path])
    try fixture.success(["skills", "add", fixture.source.path, "--agent", "codex"])
    try fixture.success(["watch", "add", mirror.path])
    let sources = try #require(try declaration(fixture)["sources"] as? [String: Any])
    #expect(Set(sources.keys) == ["source", "mirror-source"])
  }
}
