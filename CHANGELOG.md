# Changelog

User-visible changes are recorded here in Keep a Changelog style. Versioning
follows the [family standard](https://github.com/agents-tools/.github/blob/master/VERSIONING.md);
publication follows the [release checklist](Documentation/Reference/Release.md).

## Unreleased

### Added

- Skill update previews show resolved versions, executable-mode changes and
  per-agent membership, including added, removed, unchanged and changed install
  modes. Missing resolved state is identified as unrecorded membership.
- Skill update completions include available old and new versions. JSON v1
  previews add version, executable and membership metadata.

### Changed

- **Breaking**: Require macOS 26 or later. Building from source requires Swift
  6.3 or later. Upgrade macOS before installing the release that ships this
  requirement.
- `agents update` prepares one combined skill and instruction preview;
  `--apply` commits that preparation and merged state in one transaction, then
  prints completions. Failures report the confirmed apply outcome, and recovery
  retries the whole preparation.

## [0.1.1] - 2026-10-20

Built on agents-tools/core 0.1.1.

### Fixed

- Sources accept typed selectors, as in
  `agents skills add larksuite/cli@from:1.0.0@skill:lark-base`: `@branch:`,
  `@ref:`, `@revision:`, `@exact:`, `@from:`, `@minor:`, `@path:`, and
  `@skill:`.
- Adding a source whose last path component another source already uses, such
  as a second `…/skills` repository, declares it under a prefixed alias like
  `anthropics-skills` instead of failing.

## [0.1.0] - 2026-10-19

The first release of `agents`, built on agents-tools/core 0.1.0.

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
- Adding or installing a skill never replaces a directory, file, or link that
  the scope's lock does not manage, such as a hand-written skill.

[0.1.1]: https://github.com/agents-tools/cli/releases/tag/0.1.1
[0.1.0]: https://github.com/agents-tools/cli/releases/tag/0.1.0
