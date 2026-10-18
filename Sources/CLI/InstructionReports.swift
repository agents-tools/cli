import AgentsCore
import AgentsInstructions
import AgentsSkills

struct SectionItem: Encodable {
  let name: String
  let source: String
  let revision: String?
  let version: String?
  let path: String
  let hash: String

  init(_ section: LockedSection) {
    name = section.name
    source = section.source
    revision = section.revision
    version = section.version
    path = section.path
    hash = section.hash
  }
}

struct InstructionSourceReport: Encodable {
  let schemaVersion = 1
  let kind = "source"
  let scope: String
  let source: String
  let sections: [AvailableSection]

  init(scope: String, outcome: InstructionAddOutcome) {
    self.scope = scope
    source = outcome.sourceID
    sections = outcome.available.map(AvailableSection.init)
  }
}

struct AvailableSection: Encodable {
  let heading: String
  let section: SectionItem

  init(_ unit: InstructionUnit) {
    heading = unit.section.heading
    section = SectionItem(unit.record)
  }
}

struct InstructionListReport: Encodable {
  let schemaVersion = 1
  let kind = "installed"
  let scope: String
  let sections: [SectionItem]
  let targets: [InstructionTargetItem]
  let prompts: [PromptItem]

  init(scope: String, locked: LockedInstructions) {
    self.scope = scope
    sections = locked.sections.map(SectionItem.init)
    targets = locked.targets.sorted { $0.key < $1.key }.map {
      InstructionTargetItem(target: $0.key, record: $0.value)
    }
    prompts = locked.chatgpt.sorted { $0.key < $1.key }.map {
      PromptItem(name: $0.key, prompt: $0.value)
    }
  }
}

struct InstructionTargetItem: Encodable {
  let target: String
  let agents: [String]
  let headingOffset: Int?
  let `import`: String?
  let blockHash: String
  let created: Bool

  init(target: String, record: LockedTarget) {
    self.target = target
    agents = record.agents.map(\.rawValue).sorted()
    headingOffset = record.headingOffset
    `import` = record.import
    blockHash = record.blockHash
    created = record.created
  }
}

struct PromptItem: Encodable {
  let name: String
  let sections: [SectionItem]
  let append: String?

  init(name: String, prompt: LockedPrompt) {
    self.name = name
    sections = prompt.sections.map(SectionItem.init)
    append = prompt.append
  }
}

struct InstructionPreviewReport: Encodable {
  let schemaVersion = 1
  let scope: String
  let changed: Bool
  let instructions: InstructionChanges

  init(scope: String, instructions: InstructionChanges) {
    self.scope = scope
    changed = instructions.changed
    self.instructions = instructions
  }
}

struct InstructionChanges: Encodable {
  let changed: Bool
  let lockMissing: Bool
  let sections: [SectionChange]
  let targets: [InstructionTargetChangeItem]
  let changedPrompts: [String]

  init(_ report: InstructionUpdateReport) {
    lockMissing = report.lockMissing
    sections = report.sections.map(SectionChange.init)
    targets = report.targets.map(InstructionTargetChangeItem.init)
    changedPrompts = report.changedPrompts
    changed = report.hasChanges
  }
}

struct SectionChange: Encodable {
  let before: SectionItem?
  let after: SectionItem?

  init(_ change: InstructionSectionChange) {
    before = change.before.map(SectionItem.init)
    after = change.after.map(SectionItem.init)
  }
}

struct InstructionTargetChangeItem: Encodable {
  let target: String
  let path: String
  let changed: Bool
  let agentsChanged: Bool
  let beforeAgents: [String]?
  let afterAgents: [String]
  let before: FileEntry?
  let after: FileEntry?
  let drift: String?
  let adoptedSections: [String]
  let conflicts: [InstructionConflictItem]

  init(_ change: InstructionTargetChange) {
    target = change.target
    path = change.url.path
    changed = change.changed
    agentsChanged = change.agentsChanged
    beforeAgents = change.beforeAgents?.map(\.rawValue)
    afterAgents = change.afterAgents.map(\.rawValue)
    before = change.before.map { FileEntry(.file($0)) }
    after = change.after.map { FileEntry(.file($0)) }
    switch change.drift {
    case .clean: drift = "clean"
    case .drifted: drift = "drifted"
    case .missingBlock: drift = "missingBlock"
    case nil: drift = nil
    }
    adoptedSections = change.assembly.adoptedSections
    conflicts = change.assembly.conflicts.map(InstructionConflictItem.init)
  }

  private enum CodingKeys: String, CodingKey {
    case target, path, changed, agentsChanged, beforeAgents, afterAgents
    case before, after, drift, adoptedSections, conflicts
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(target, forKey: .target)
    try container.encode(path, forKey: .path)
    try container.encode(changed, forKey: .changed)
    try container.encode(agentsChanged, forKey: .agentsChanged)
    try container.encode(beforeAgents, forKey: .beforeAgents)
    try container.encode(afterAgents, forKey: .afterAgents)
    try container.encodeIfPresent(before, forKey: .before)
    try container.encodeIfPresent(after, forKey: .after)
    try container.encodeIfPresent(drift, forKey: .drift)
    try container.encode(adoptedSections, forKey: .adoptedSections)
    try container.encode(conflicts, forKey: .conflicts)
  }
}

struct InstructionConflictItem: Encodable {
  let section: String
  let existing: String
  let proposed: String
  let difference: String

  init(_ conflict: InstructionConflict) {
    section = conflict.sectionID
    existing = conflict.existing
    proposed = conflict.proposed
    difference = conflict.difference
  }
}

struct InstallReport: Encodable {
  let schemaVersion = 1
  let scope: String
  let skills: [RestoredSkill]
  let instructions: InstructionChanges

  init(scope: String, skills: [InstallResult], instructions: InstructionChanges) {
    self.scope = scope
    self.skills = skills.map(RestoredSkill.init)
    self.instructions = instructions
  }
}

struct RestoredSkill: Encodable {
  let name: String
  let agent: String
  let mode: String
  let path: String

  init(_ result: InstallResult) {
    name = result.skill
    agent = result.agent.rawValue
    mode = result.mode.rawValue
    path = result.path
  }
}
