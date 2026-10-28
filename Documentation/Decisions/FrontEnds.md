# Front Ends

## Status

Accepted

## Context

Core owns sources, declarations, locks, discovery, installation and recovery.
The `agents` CLI and the skills-only `skill` CLI already share core and its
state. A macOS GUI will manage everything the CLI manages. Comparable desktop
apps keep their own databases, so their view of intent and the files on disk
can disagree with each other and with any CLI.

## Decision

- **Core owns behavior.** The `agents` CLI, the macOS GUI and the `skill` CLI
  are front ends over core and one shared state. Every GUI operation has a CLI
  command. The GUI links core directly, and the GUI and CLI release together
  at the same version.
- **No GUI-private state.** Business facts live in `Agents.swift`, the lock and
  core-managed state; the GUI keeps only interface preferences. Presets and
  collections are named groups in the manifest. Moving a setup to another
  machine means syncing `Agents.swift` and the lock and running
  `agents install`.
- **Previews bind to apply.** The GUI uses core's prepare and apply. If the
  manifest or targets change during a preview, apply re-checks and refreshes
  the plan.
- **Manifest editing.** The GUI edits manifest constructs that core can edit
  exactly and shows the rest read-only, with a way to open the file in an
  editor.
- **Updates.** The GUI checks and notifies, and applies on request.
- **On-device assistance.** Where Apple's on-device model is available, the
  GUI uses Foundation Models to explain a skill, translate its description,
  summarize an update and explain a pending executable component. These
  features are hidden when the model is unavailable and can be turned off.
- **The `skill` CLI** remains the skills-only entry point over the same core
  and state, released on the same core version.
- **The GUI** lives in its own repository in the agents-tools organization and
  ships as a notarized Homebrew cask.
- **Usage guidance.** A skill published by the agents-tools organization
  teaches agents and people to use `agents` and write `Agents.swift`.

## Consequences

- Every capability lands in core before a front end exposes it.
- The CLI's machine-readable output and core's API are the contracts the GUI
  and `skill` depend on; incompatible changes follow the family versioning
  policy for each consumer.
- The GUI watches the manifest, lock and targets and refreshes from core
  diagnostics rather than caching status.
- Foundation Models features exist only in the GUI, because the CLI also runs
  on Linux.

## Alternatives Considered

- **A GUI that shells out to the CLI.** Progress, cancellation and file
  watching would be limited to what text output carries.
- **A GUI database for intent.** The CLI could not read it, and state would
  diverge.
- **Retire the `skill` CLI.** Skills-only installers remain widely used, and
  `skill` serves them at little cost while it carries no logic of its own.
- **A cloud LLM client in the GUI.** Adds provider keys, cost and outbound
  data, and turns a manager into a coding assistant.
- **Automatic update apply.** Deferred; checks and one-step apply keep every
  change reviewed.

## Related Documentation

- Accepted by the repository owner (showxu) on 2026-10-28.
- Product scope: [Product Scope](ProductScope.md)
- Executable approval the GUI presents: [core decisions](https://github.com/agents-tools/core/tree/master/Documentation/Decisions)
- Current architecture: [Architecture](../Architecture/README.md)
