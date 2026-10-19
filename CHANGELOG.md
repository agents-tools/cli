# Changelog

User-visible changes are recorded here in Keep a Changelog style. Versioning
follows the [family standard](https://github.com/agents-tools/.github/blob/master/VERSIONING.md);
publication follows the [release checklist](Documentation/Reference/Release.md).

## Unreleased

### Added

- Skill commands to add, list, remove, update, and initialize skills, with
  locked installation and diagnostics for project and user scopes.
- Instruction lifecycle commands, managed agent-file sections, and rendering
  of named ChatGPT prompts from locked content.
- Source subscriptions with `watch`, upstream status, file diffs, and
  acknowledgment of seen changes.
- Readable terminal reports and unified diffs alongside JSON output.

### Fixed

- Top-level updates report only changed skills, instructions, and prompts.
- Concise Git errors include actionable remedies.
