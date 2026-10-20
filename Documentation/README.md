# Documentation

- [CLI reference](Reference/CLI.md): shipped commands, options, output, errors,
  state locations, and JSON contracts.
- [JSON schemas](Reference/Schemas/): machine-readable schemas for list,
  update previews, watch status and diffs, installation, and doctor.
- [Release checklist](Reference/Release.md): prepare and verify release commits,
  publish signed tags, and validate the Homebrew formula.
- [Terminal demo](Reference/TerminalDemo.md): record the README session and
  reproduce its light and dark exports.
- [Logo](../.github/assets/logo/): rendered from the agents icon in
  [agents-tools/.github](https://github.com/agents-tools/.github/blob/master/DESIGN.md).
- [README terminal assets](../.github/assets/terminal/): the scripted session,
  generated recording, and light/dark SVGs.

The package manifest owns target and dependency configuration. Shared lifecycle
architecture is documented in
[core](https://github.com/agents-tools/core/tree/master/Documentation/Architecture).
Its [command proposal](https://github.com/agents-tools/core/blob/master/Documentation/Proposals/AgentInstructions.md)
describes the broader command design; the CLI reference describes the implemented
surface in this repository.
