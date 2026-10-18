# CLI Reference

`agents` manages declared skills and instructions. Resolution, installation,
state, and recovery operations use `AgentsCore`, `AgentsSkills`, and
`AgentsInstructions`.

## Commands

```text
agents skills add <source> [names…] [--all]
agents skills list [source] [--json]
agents skills remove <names…>
agents skills update [names…] [--apply | --json]
agents skills init [name]
agents instructions add <source> [names…] [--replace]
agents instructions list [source] [--json]
agents instructions remove <names…>
agents instructions update [--apply | --json]
agents instructions render chatgpt <prompt>
agents instructions init <name>
agents install [--json]
agents update [--apply | --json]
agents doctor [--root <dir>…] [--json]
```

`agents --help`, `agents skills --help`, `agents instructions --help`, and each
command's `--help` describe their options. Running a group without a subcommand prints help. `agents --version`
prints `agents X.Y.Z` and is available only on the root command; the version
constant lives in `Sources/CLI/EntryPoint.swift`.

Root overview: "Manage agent skills and instructions from declared sources."
Root help includes:

```text
Examples:
  agents skills add github.com/owner/skills pdf-forms
  agents skills list
  agents instructions add <source> canonical-artifacts
  agents instructions render chatgpt <prompt> | pbcopy
  agents install
  agents update               Preview what re-resolving would change
  agents update --apply       Write the updates and the new lock
```

## Shared Options

| Option | Meaning | Commands |
| --- | --- | --- |
| `--scope project\|user` | Where state lives: project (./.agent) or user (~/.agents). Default: project. | All lifecycle and read commands; `init` uses the current directory |
| `--agent <agent>` | Agent to install for: codex, claude-code, cursor, gemini-cli or opencode. Repeat for several. Default: the agents already recorded for this skill or source, else the declaration's agents, else codex and claude-code. | `skills add` |
| `--agent <agent>` | Limit to this agent: codex, claude-code, cursor, gemini-cli or opencode. Repeat for several. Default: all recipients. | `skills list`, `skills remove`, `doctor` |
| `--agent <agent>` | Set the scope's entire instruction section list recipients. Repeat for several. Default: recorded instruction agents, else declaration agents, else codex and claude-code. | `instructions add`, `instructions remove`, `instructions update` |
| `--path <subdir>` | Search this subdirectory of the source. | Both kinds' `add` and `list <source>` |
| `--full-depth` | Discover recursively beyond conventional skill directories | `skills add`, `skills list <source>` |
| `--mode link\|copy\|edit` | How to install: link (default), copy, or edit (a live link to a local source). | `skills add` |
| `--root <dir>…` | Audit these project directories read-only. Repeat for several. | `doctor` |
| `--json` | Emit a versioned JSON report on stdout | Both kinds' `list`, `install`, `doctor`, all update previews |

Agents are `codex`, `claude-code`, `cursor`, `gemini-cli`, and `opencode`.
For instruction recipients, Cursor supports project scope only. ChatGPT is a
named render target, not a `--agent` value. Core also accepts `claude` and
`gemini` as input aliases. Output uses canonical IDs. On skill add, omitted
recipients use the agents already recorded for the skill or source, then
declaration defaults (initially Codex and Claude Code). On skill list, skill
remove, and doctor, omission covers all recipients. Source listing shows
available content regardless of recipients.
Doctor's agent filter limits skill installation checks; skill source checks and
instruction diagnostics cover the scope. Instruction targets can be shared by
several agents, and are audited as physical files.

Skill updates use declared paths, recipients, and modes. Instruction updates
use declared paths and section order; `instructions update --agent` previews
replacement recipients and persists them only with `--apply`. `instructions remove --agent` removes the named sections and sets recipients for the remaining
list; it does not remove only one agent's copy. Read commands do not accept
instruction recipient overrides. Installation restores recipients recorded in
the lock. Top-level update and install accept no recipient or mode override.
`--path` always refers to source discovery, never a project root;
change directory for project operations or use doctor's `--root` for auditing.
Unsupported options are usage errors.

## Adding and Inspecting Skills

`source` is a local path, Git URL or shorthand accepted by core, well-known
HTTP source, or an existing declaration alias. Add writes the declaration,
installations, and lock together.

`<names>`: Skills to add. Omit to add the source's only skill, or to list the
choices when it has several. Explicit names select those skills. `--all` selects
all current and future members on unnamed updates; combining names and `--all`
is a usage error.

`link` links verified, pinned cache content. `copy` installs pinned copies.
Both require a Git repository for local sources and read committed content.
`edit` links live local directories and accepts no requirement.

Requirement options on add map directly to declaration forms:

| Option | Declaration | Matching versions |
| --- | --- | --- |
| `--branch main` | `"branch": "main"` | Git branch |
| `--revision <rev>` | `"revision": "<rev>"` | Git revision |
| `--exact 1.2.3` | `"exact": "1.2.3"` | Exact semantic version |
| `--from 1.2.3` | `"from": "1.2.3"` | At least 1.2.3, below 2.0.0 |
| `--up-to-next-minor-from 1.2.3` | `"upToNextMinor": "1.2.3"` | At least 1.2.3, below 1.3.0 |
| `--from 1.2.3 --to 1.8.0` | `"from": "1.2.3", "to": "1.8.0"` | Half-open range [1.2.3, 1.8.0) |

Choose one requirement form; `--to` requires `--from`. With no requirement,
core uses the latest version tag or the default branch if there are no tags.

`skills list` lists managed lock records, including missing or drifted installs,
one row per recipient. `skills list <source>` inspects what a source provides.
Source discovery paths can refer to cache materializations and are not stable
identifiers; use the source ID and skill name for identity.

## Instructions

Instruction sources are Git URLs, shorthands, local Git roots, or existing
source aliases. Discovery reads committed `*.md` files directly inside
`instructions/` and `.agents/instructions/`, relative to the source root or
`--path` subdirectory. Local paths must identify the Git root. Instruction add
supports the same requirement options as skill add; instructions do not have
installation modes, recursive discovery, or `--all`.

`instructions add <source> [names…]` appends sections in argument order to the
scope's ordered list. With no names, one available section is added; several
available sections are listed for selection without writing declarations or
locks. `instructions list <source>` lists available sections;
`instructions list` reports locked sections, physical targets and named prompts,
including missing targets. Doctor reports their disk status.

Core writes one managed block per physical target and preserves custom content
around it. The block and its adjacent separating blank lines belong to core;
removing the block also removes those separators. Project Codex, Claude Code,
Cursor, and OpenCode share `AGENTS.md`;
Gemini CLI uses `GEMINI.md`. User targets are the corresponding agent files
under their configuration directories. Headings shift below an existing title.
When a project Claude file exists, core adds a managed import of `AGENTS.md`
where needed. Existing forwarding and custom content are preserved.

Conflicting custom sections stop add with differences in the diagnostic.
`--replace` displays before/after target snapshots before replacing conflicts.
`instructions remove <names…>` removes sections from file targets and ChatGPT
prompts. Use `source-alias:name` if a bare name is ambiguous. Empty managed
blocks are removed; files created by core are deleted only when no custom
content remains. `instructions init <name>` creates `<name>.md` in the current
directory and rejects an existing file.

Declare named ChatGPT prompts in the scope's `agents.json`, using an existing
source alias (here `rules`):

```json
{
  "instructions": {
    "sections": ["rules:canonical-artifacts"],
    "chatgpt": {
      "weekly": {
        "sections": ["rules:canonical-artifacts"],
        "append": "prompt-custom.md"
      }
    }
  }
}
```

Merge this fragment with the declaration's existing sources and selections.
`append` is optional and relative to the project root or HOME for user scope.
Run `agents instructions update` to preview, then `--apply` to lock the prompt.
`agents instructions render chatgpt weekly` writes exactly the locked sections
in declared order, followed by the current append file bytes, without markers
or status text. It does not resolve upstream versions. An absent prompt or one
without locked sections fails. Add `--scope user` for a user prompt.

Update previews list changed prompts. After apply, the CLI tells the user to
re-paste them; removed prompts must be cleared in ChatGPT. Core detects changes
to section bytes, membership, order, or append path. Edits to the append file's
contents are read at render time and are not tracked as prompt changes.

## Update, Restore, Remove, and Initialize

All update commands preview by default, comparing newly resolved declarations
against disk. `skills update <names…>` limits resolution to named skills;
`agents update` and unnamed `skills update` reconcile every declared skill,
including membership changes in `all` selections. `instructions update` resolves
all declared sections and ChatGPT prompts. Top-level `update` handles skills,
then instructions.

`--apply` prints old/new revisions, hashes, and full before/after file snapshots
before core replaces targets and lock together. File output includes deletion,
directory, symbolic-link destination, text, and binary bytes (base64). This is
a full snapshot comparison, not a minimal unified patch. A preview can become
stale; `--apply` resolves again and displays the content it will actually write.
`--json --apply` is a usage error.

`install` restores skills, then instruction targets, using exact locked pins,
hashes, modes, recipients, and heading offsets. It does not resolve newer versions and takes no source argument. Unavailable pins or content
that fails digest verification cause failure.

`skills remove` requires names and removes their declarations, files, and lock entries.
With `--agent`, it removes only those recipients. Removing a member of an `all`
selection records an exclusion so an update does not reinstall it.

`skills init [name]` creates a skill directory and `SKILL.md` in the current directory;
without a name it creates `SKILL.md` directly there. Existing files are errors.

Top-level install and update run one core operation per kind, in order. Each
kind commits its own transaction; an instruction failure does not roll back a
completed skill operation. A failing command exits 1 and emits no successful
JSON report. Recovery retry is scoped to the operation that reported recovery.

## Doctor and State

Doctor reports skills first, then instructions for each root. Skill checks
include missing installations, drift, broken links, newer matching source
revisions, and uncommitted source content. Instruction checks include missing
or drifted blocks, adoption/conflicts, missing locks, sections at both scopes,
Claude forwarding and ancestor files, Codex override files and size limits,
source changes, and invalid configuration. `--root` audits both kinds.
`--root` accepts multiple directories, either after one option or repeated.
Each root is an explicit project directory; `--root` cannot combine with user
scope. A nonexistent root is an error. Without roots, project scope uses the
current directory and user scope uses HOME.

| Scope | Declaration | Lock | Cache |
| --- | --- | --- | --- |
| Project | `.agent/agents.json` | `.agent/agents.resolved` | `.agent/cache/` |
| User | `~/.agents/agents.json` | `~/.agents/agents.resolved` | `~/.agents/cache/` |

Project roots are the current directory, not a search up the Git ancestry.
Core resolves installation locations, including `CODEX_HOME`,
`CLAUDE_CONFIG_DIR`, and `XDG_CONFIG_HOME` when applicable. User state remains
under HOME's `.agents` directory.

Read commands and previews do not write declarations, locks, or installations
during normal operation. They may fetch/cache source data. If core recovers an
interrupted transaction on any operation, the CLI reports recovery on stderr
and retries that operation once. A second recovery or any other failure stops
the command. Recovery can restore files even when triggered by a read command.

## Output and Exit Status

Human-readable stdout is the default. Commands are non-interactive and never
prompt; add, remove, init, and install perform their named actions immediately.
Only `update --apply` writes an update. Diagnostics and recovery notices go to
stderr. Errors are one line containing the cause and a suggested action.
Terminal control characters in human-readable source text are replaced by spaces.
ChatGPT render preserves its content exactly, including whitespace and the
append file's final newline behavior; only diagnostics go to stderr.

| Code | Meaning |
| --- | --- |
| `0` | Success, including help/version, unchanged previews, and doctor warnings |
| `1` | Operation failure or a completed doctor report containing an error check |
| `64` | Invalid usage, including unknown commands, options, or invalid option combinations |

Doctor's `ok` means there are no error checks; warnings do not make it false.
Instruction `invalidTarget`, `conflict`, `invalidConfiguration`, and
`stateUnavailable` diagnostics are errors. Other instruction diagnostics,
including drift and missing blocks, are warnings. Skill severity is supplied
by core.
A failed operation emits no successful JSON report. JSON stdout contains only
one object and a trailing newline; recovery notices remain on stderr.

## JSON Schemas

All reports have integer `schemaVersion: 1`. Object keys are sorted. Arrays
follow core's deterministic ordering; instruction section lists preserve
selection order, targets and prompt names are sorted, and doctor roots retain
input order.
Optional properties are omitted when unavailable, never encoded as `null`.
Filesystem paths, including update file `path` fields, are absolute except
instruction section `path` (source-relative), `target` keys (project-relative,
`~`-relative for user targets under HOME, otherwise absolute), and prompt
`append` paths (scope-root-relative). File bytes use standard base64. Missing
`before` or `after` means that entry is absent, distinct from an empty file or
directory.
Clients should ignore unknown properties; incompatible changes require a new
schema version. Diagnostic IDs are core-defined strings, not a closed enum.

| Command | Schema | Required root fields |
| --- | --- | --- |
| `skills list --json` | [Installed list](Schemas/installed-list.schema.json) | `schemaVersion`, `kind: "installed"`, `scope`, `skills` |
| `skills list <source> --json` | [Source list](Schemas/source-list.schema.json) | `schemaVersion`, `kind: "source"`, `scope`, `source`, `skills` |
| `update --json`, `skills update --json` | [Update](Schemas/update.schema.json) | `schemaVersion`, `scope`, `changed`, `skills`; top-level update also emits `instructions` |
| `instructions list --json` | [Managed instructions](Schemas/instructions-installed-list.schema.json) | `schemaVersion`, `kind: "installed"`, `scope`, `sections`, `targets`, `prompts` |
| `instructions list <source> --json` | [Instruction source](Schemas/instructions-source-list.schema.json) | `schemaVersion`, `kind: "source"`, `scope`, `source`, `sections` |
| `instructions update --json` | [Instruction update](Schemas/instructions-update.schema.json) | `schemaVersion`, `scope`, `changed`, `instructions` |
| `install --json` | [Install](Schemas/install.schema.json) | `schemaVersion`, `scope`, `skills`, `instructions` |
| `doctor --json` | [Doctor](Schemas/doctor.schema.json) | `schemaVersion`, `ok`, `roots` |

An empty installed list:

```json
{"schemaVersion":1,"kind":"installed","scope":"project","skills":[]}
```

An empty skill update preview:

```json
{"schemaVersion":1,"scope":"project","changed":false,"skills":[]}
```

A healthy doctor report:

```json
{"schemaVersion":1,"ok":true,"roots":[{"root":"/project","scope":"project","ok":true,"checks":[]}]}
```

Top-level update compatibly adds `instructions` to v1 and computes root
`changed` across both kinds. `skills update` retains its existing shape.
Doctor checks add `kind: "skills" | "instructions"`; existing fields and IDs
remain, and instruction IDs use core's diagnostic names. Consumers distinguish
checks by `(kind, id)` because kinds may use the same ID.

The shared [instruction definitions](Schemas/instructions.schema.json) describe:

- `sections`: pin changes with optional `before` and `after` section records.
- `targets`: all affected physical files, each with `target`, absolute `path`,
  `changed`, optional `before`/`after` file snapshots, optional `drift`,
  `adoptedSections`, and `conflicts` with existing/proposed text and difference.
- `changedPrompts`: prompt names whose content definition changed.
- `lockMissing`: no scope lock existed when the operation began.
- `changed`: a section pin, target bytes, or prompt changed, or targets need a
  missing lock recorded. Recipient metadata changes sharing the same physical
  target may leave this false; `--apply` still records the chosen recipients.

Instruction file snapshots use the same `{ "kind": "file", "base64": "…" }`
shape as skill files. `install --json` reports restored skill rows and
instruction restoration differences; instruction `sections` and
`changedPrompts` are empty because install never resolves new content.
The definitions are CLI-owned and do not expose core's encoded lock objects.
