# Documentation

This directory indexes repository-native documentation for `agents-tools/cli`.

## Areas

- [Architecture](Architecture/README.md): current truth for package structure
  and documentation placement
- [Proposals](Proposals/README.md): design-in-progress and open alternatives
- [Decisions](Decisions/README.md): accepted decisions and rationale
- [Migrations](Migrations/README.md): transition and cutover records
- [Archive](Archive/README.md): retired or superseded material kept for record
- [CLI reference](Reference/CLI.md): shipped commands, options, output, errors,
  state locations, and JSON contracts.
- [JSON schemas](Reference/Schemas/): machine-readable schemas for list,
  update previews, watch status and diffs, installation, and doctor.
- [Release checklist](Reference/Release.md): prepare and verify release commits,
  publish signed tags, and validate the Homebrew formula.
- [Terminal demo maintenance](Reference/TerminalDemo.md): review CI recording
  drift and locally render and check terminal SVGs and the social preview.
- [Logo](../.github/assets/logo/): rendered from the agents icon in
  [agents-tools/.github](https://github.com/agents-tools/.github/blob/master/DESIGN.md).
- [README terminal assets](../.github/assets/terminal/): the scripted session,
  generated recording, and light/dark SVGs.
- [Social preview](../.github/assets/social-preview/social-preview.png): the
  catalog-driven repository card rendered and checked locally.

The required CI checks are `policy / policy` and `validate / result`. The demo
job re-records `recording.json` and uploads it on drift; local asset rendering
uses the github-readme-design toolchain and `agents-tools/.github`'s DESIGN,
fonts and catalog.

The package manifest owns target and dependency configuration. Shared lifecycle
architecture is documented in
[core](https://github.com/agents-tools/core/tree/master/Documentation/Architecture).
Its [command proposal](https://github.com/agents-tools/core/blob/master/Documentation/Proposals/AgentInstructions.md)
describes the broader command design; the CLI reference describes the implemented
surface in this repository.
