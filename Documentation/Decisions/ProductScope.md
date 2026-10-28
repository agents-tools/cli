# Product Scope

## Status

Accepted

## Context

`agents` manages skills and instructions for coding agents. Comparable tools
each cover part of the space: Microsoft APM is the most complete package
manager for agent configuration, rulesync spans the most components and
targets, npx skills is the most used skills installer, and several desktop
apps manage skills. The next stage turns `agents` into a full management CLI
with a macOS GUI.

## Decision

- **Independent tool.** `agents` has its own manifest and engine. It neither
  adopts `apm.yml` as its manifest nor delegates to another manager.
  Configurations from APM, rulesync and npx skills are imported one way.
- **Scope.** Everything APM can do for the supported agents, plus the
  components rulesync covers beyond it, such as permissions and ignore rules,
  each covered or exceeded. Exclusions are explicit: agents beyond the
  supported set, a built-in general-purpose LLM client, a web GUI, desktop GUIs
  on other platforms, telemetry by default and a Windows CLI.
- **Supported agents.** Claude Code, Codex, Cursor, Gemini CLI and OpenCode, at
  their current stable releases. Support claims are verified against those
  clients, and `doctor` reports an installed client older than the verified
  release.
- **Platforms.** The CLI runs on macOS 15, 26 and 27 and on Linux. The GUI runs
  on macOS.
- **Conventions.** Content keeps its ecosystem formats: a skill is a directory
  with `SKILL.md`, and instructions are Markdown with front matter. A
  repository laid out by those conventions is usable as a source without an
  `Agents.swift`.

## Consequences

- Core and the CLI build and test on Linux in CI.
- Each scope item is tracked against the comparable tools' capabilities, and
  each exclusion keeps its reason.
- New components and agents enter through core's capability registry and
  client verification.

## Alternatives Considered

- **Read and write `apm.yml` as the manifest.** Couples the model to APM's
  package semantics and leaves two managers owning the same outputs.
- **Build on the APM CLI.** Adds a Python runtime and limits the product to
  APM's behavior.
- **Match upstream agent counts.** Breadth across dozens of agents would come
  at the cost of verified depth on the agents in use.

## Related Documentation

- Accepted by the repository owner (showxu) on 2026-10-28.
- Front ends over core: [Front Ends](FrontEnds.md)
- Manifest, components and approval: [core decisions](https://github.com/agents-tools/core/tree/master/Documentation/Decisions)
- Current commands: [CLI reference](../Reference/CLI.md)
