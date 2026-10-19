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
agents watch
agents watch add <source> [--path <dir>] [requirement options] [--scope project|user]
agents watch status [--json] [--scope project|user]
agents watch diff <source> [name] [--kind skill|instructions|artifact] [--json] [--scope project|user]
agents watch seen <source> [--revision <rev>] [--scope project|user]
agents watch remove <source> [--scope project|user]
agents install [--json]
agents update [--apply | --json]
agents doctor [--root <dir>…] [--json]
```

`agents --help`, `agents skills --help`, `agents instructions --help`,
`agents watch --help`, and each command's `--help` describe their options.
Running a group without a subcommand prints help, except `agents watch`, which
runs `watch status` and accepts its options. `agents --version`
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
| `--path <subdir>` | Search this subdirectory of the source. | Both kinds' `add` and `list <source>`, `watch add` |
| `--full-depth` | Discover recursively beyond conventional skill directories | `skills add`, `skills list <source>` |
| `--mode link\|copy\|edit` | How to install: link (default), copy, or edit (a live link to a local source). | `skills add` |
| `--root <dir>…` | Audit these project directories read-only. Repeat for several. | `doctor` |
| `--json` | Emit a versioned JSON report on stdout | Both kinds' `list`, `install`, `doctor`, all update previews, `watch status`, `watch diff` |

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
installations, and lock together. A skill directory, file, or link that the
scope's lock does not manage is never replaced: add and install stop before any
change and name the path, so move or remove it first.

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
`--replace` displays a unified target diff before replacing conflicts.
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
`agents instructions render chatgpt weekly` writes the locked sections in
declared order, followed by the current append file content, without markers
or status text. Tabs and line breaks are preserved; other control characters
use visible escapes. It does not resolve upstream versions. An absent prompt or one
without locked sections fails. Add `--scope user` for a user prompt.

Update previews and `--apply` list changed prompts. Re-paste changed prompts;
removed prompts must be cleared in ChatGPT. Core detects changes
to section bytes, membership, order, or append path. Edits to the append file's
contents are read at render time and are not tracked as prompt changes.

## Watch

`watch add <source>` subscribes without installing content and records the
current baseline as seen. Repeating add acknowledges current content again.
Sources can be declared aliases, source locations, or existing source IDs.
`--path` and requirement options use the same forms as `skills add`. A local
source must be a Git repository. Git subscriptions follow the declared branch,
or the default branch; version and revision requirements do not select the
watched head. Well-known subscriptions follow the index.

`watch status`, also available as `agents watch`, reports subscriptions in
core's order. Git revisions are abbreviated to seven characters:

```text
local:~/Developer/team-rules  1 commit since 6c09c94 (now 9661957)
  ~ changed  code-review (instructions)   1 file
  ~ changed  pdf   1 file
```

The Git count is commits reachable from the current head but not the seen
revision. A well-known source shows `N artifacts changed` (singular for one),
or `up to date`. Instruction and artifact names carry `(instructions)` or
`(artifact)`; skills have no suffix. Changed items show `1 file` or `N files`;
new and removed items omit the file count. An empty scope prints
`No watched sources.`

`watch diff <source> [name]` prints each changed item's heading and unified
line diffs with three lines of context. Skill paths are relative to the skill
root and prefixed by the skill name, such as `pdf/SKILL.md`. Instruction and
artifact paths are relative to the item.
`--kind skill|instructions|artifact` filters changes and disambiguates shared
names. With no matching changes, diff prints `up to date`.

```text
~ changed  code-review (instructions)  local:~/Developer/team-rules  6c09c94 -> 9661957
--- a/code-review.md
+++ b/code-review.md
@@ -2,7 +2,7 @@
 Review checklist:
 Read the change.
 Check correctness.
-Review the code.
+Review the code and tests.
 Check tests.
 Check edge cases.
 Record findings.
```

Mode changes print `mode pdf/run.sh: 644 -> 755`; unchanged modes are omitted.
Binary content prints `Binary file <path> differs`. Links print
`link <path>: <old> -> <new>` (`none` for an absent link); directories print
`directory <path> added` or `directory <path> removed`.

`watch seen <source>` acknowledges current content. `--revision <rev>` resolves
a Git revision to its full commit ID and can select an older commit. Well-known
sources do not accept `--revision`. `watch remove <source>` removes the
subscription and baseline while preserving declarations, locks, and installed
content. Diff, seen, and remove accept a subscribed alias, source ID, or location.

Mutation confirmations use normalized source IDs:

```text
Watching local:~/Developer/team-rules from 6c09c94.
Marked local:~/Developer/team-rules seen at 9661957.
Stopped watching local:~/Developer/team-rules; installations are unchanged.
```

Well-known confirmations omit revisions: `Watching <source ID>.` and
`Marked <source ID> seen.` Add, seen, and remove do not accept `--json`.
Status and diff emit one JSON object each with `--json`; revisions remain full.
They can fetch upstream content without changing declarations, locks, watch
baselines, installations, or source working trees. Uncommitted source files are
ignored. Scheduling checks is left to the caller.

Watch baselines live in `.agent/agents.watch` for project scope or
`~/.agents/agents.watch` for user scope. `agents.json` owns subscriptions.
A missing subscription suggests `run 'agents watch' to list subscriptions`;
an invalid revision suggests providing a Git revision that resolves to a commit
in the watched source. Operation failures exit 1; invalid options and unknown
subcommands exit 64, as elsewhere in the CLI.

## Update, Restore, Remove, and Initialize

All update commands preview by default, comparing newly resolved declarations
against disk. `skills update <names…>` limits resolution to named skills;
`agents update` and unnamed `skills update` reconcile every declared skill,
including membership changes in `all` selections. `instructions update` resolves
all declared sections and ChatGPT prompts. Top-level `update` handles skills,
then instructions.

Human output for top-level `update` and `update --apply` includes only changed
items. When neither kind has changes, they print `No changes.` once. The
kind-specific commands keep `No skill changes.` and `No instruction changes.`
for unchanged runs.

Human update item lines use `+ new`, `~ changed`, `= repinned`, and `- removed`.
Repinned means only the pin moved and content is identical. Items sort in that
order, then by name, with skills before instructions for the same name.
Top-level previews combine both kinds; `--apply` keeps core's skill-then-instruction
operation order and sorts within each operation.
Instruction names carry `(instructions)`. Revisions use seven characters;
instruction versions appear as `1.2.0 (abc1234)`, while skill updates show
revisions. Item summaries omit hashes. Live edit records show `none` for pins;
a pinless result with no file differences is reported as changed.

```text
~ changed  code-review (instructions)  local:~/Developer/team-rules  6c09c94 -> 9661957
= repinned  commits (instructions)  local:~/Developer/team-rules  6c09c94 -> 9661957
AGENTS.md (claude-code, codex)
--- a/AGENTS.md
+++ b/AGENTS.md
@@ -3,7 +3,7 @@
 Review checklist:
 Read the change.
 Check correctness.
-Review the code.
+Review the code and tests.
 Check tests.
 Check edge cases.
 Record findings.
Preview only. Run again with --apply to write these changes.
```

Human diffs are for reading. JSON reports carry exact content bytes in base64.
Tabs print verbatim; other control characters in payload lines and upstream
text use visible escapes such as `\r`, `\x1b`, `\x00`, or `\u{202e}`. Rendered
ChatGPT Markdown preserves line breaks and tabs and uses the same escaping.

File comparisons use unified line diffs with three lines of context and
`--- a/<path>`, `+++ b/<path>`, and `@@` hunk headers. New files use
`--- /dev/null`; removed files use `+++ /dev/null`. Missing trailing newlines
are marked with `\ No newline at end of file`. Empty file creation or removal
prints only `empty file <path> added` or `empty file <path> removed`. Binary, mode,
link, and directory changes use the same rendering as watch diffs. Watch diffs
include executable-mode changes; skill update diffs compare content bytes,
links, and directories.

Skill content differences appear once per skill, using paths relative to its
root prefixed by its name. Identical changes across installations are combined.
Recipient-specific differences, such as divergent local copies, are labeled by
recipient. Installation links moving between cached snapshots are omitted.
Links to live edit targets and changes between link, copy, and edit modes remain
visible, as do symbolic links within the skill content.

```text
~ changed  pdf  local:~/Developer/team-rules  6c09c94 -> 9661957
--- a/pdf/SKILL.md
+++ b/pdf/SKILL.md
@@ -6,7 +6,7 @@
 PDF checklist:
 Open the document.
 Inspect page sizes.
-Inspect PDF pages.
+Inspect PDF pages and metadata.
 Check metadata.
 Check annotations.
 Review extracted text.
Preview only. Run again with --apply to write these changes.
```

Instruction targets print `<path> (<recipients>)` before their diff. Recipient
changes print `Recipients of AGENTS.md: codex -> claude-code, codex`, including
changes with identical file bytes. Each side lists sorted agent IDs; `none`
means no recipients or no previous lock entry.

`--apply` prints the preview before each core operation writes, followed by
`Updated <skill> for <recipients>.` for changed skills and `Updated <path>.` for
changed instruction targets. Removed skill recipients get
`Removed <skill> for <recipients>.` Skill update and removal completions print
only for changed results; unchanged skills print no completion. This also
applies to `skills update --apply`. Skill completions print as soon as the skill
operation succeeds, before instruction processing. There is no generic success
banner.
A preview can become stale; `--apply` resolves again and displays the content
it will actually write. `--json --apply` is a usage error.

Completion lines name their content and destinations:

```text
Installed pdf for claude-code, codex (link).
Added code-review, commits to AGENTS.md (claude-code, codex).
Updated pdf for claude-code, codex.
Updated AGENTS.md.
Removed commits from AGENTS.md.
Removed pdf for claude-code, codex.
```

Normal instruction adds print only the completion lines. Replacing conflicting
custom sections with `--replace` prints the conflict diff first. Instruction
removal prints target diffs before its completion lines.

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

Read commands and previews do not recover interrupted transactions or write
declarations, locks, or installations. Doctor inspects existing state without
fetching sources, writing caches, or creating locks. A pending transaction is
reported as skill check `pending-recovery` and instruction diagnostic
`pendingRecovery`. Both are error checks: the state is inconsistent until
recovery, so doctor sets `ok` to false and exits 1. Human output includes the
affected state directory, which can belong to the other scope. To finish
recovery, run `agents install --scope user` for `~/.agents`, or run
`agents install` in the project root for that project's `.agent` directory.

Commands that change a scope finish pending recovery before proceeding. When
core reports recovery, the CLI prints a notice on stderr and retries that
operation once. A second recovery or any other failure stops the command.

## Output and Exit Status

Human-readable stdout is the default. Commands are non-interactive and never
prompt; add, remove, init, and install perform their named actions immediately.
Only `update --apply` writes an update. Diagnostics and recovery notices go to
stderr. Human paths are project-relative inside the project in project scope,
`~/…` under HOME, and absolute otherwise. Local source IDs abbreviate HOME,
for example `local:~/Developer/team-rules`. Installed skill listings use the
same path rules. JSON retains full revisions, hashes, and absolute paths.

Errors preserve line breaks. The first line starts with `Error: `; every
continuation line is indented by two spaces, including Git stderr and remote
text that itself begins with `Error:`. Trailing blank lines are dropped.
Punctuation is added only when the error's last non-empty line lacks it.
The capitalized remedy is its own final sentence on a separate line, indented
by two spaces. Tabs print verbatim; all other controls within each line,
including ESC, CR, C1, and bidi controls, use visible escapes:

```text
Error: No ChatGPT prompt named 'daily' is declared.
  Declare it under instructions.chatgpt in agents.json and run 'agents instructions update --apply'.
Error: Unknown option '--all'. Did you mean '--path'?
  Run 'agents --help' for usage.
```

Git failures name the operation and source, followed by Git's diagnostics and
a remedy. For a source alias `missing` declared in `.agent/agents.json` as
`{"git": "file://localhost/missing/skills.git"}`, a failed add reports:

```text
$ agents skills add missing demo
Error: Git could not clone file://localhost/missing/skills.git.
  fatal: '/missing/skills.git' does not appear to be a git repository
  fatal: Could not read from remote repository.
  Please make sure you have the correct access rights
  and the repository exists.
  Check Git access and the source location.
```

A declared ChatGPT prompt without locked sections retains the diagnostic
`A ChatGPT prompt must have at least one locked section.`
Human-readable source text preserves tabs and visibly escapes other control
characters. ChatGPT render also preserves line breaks and the append file's
final newline behavior; only diagnostics go to stderr.

| Code | Meaning |
| --- | --- |
| `0` | Success, including help/version, unchanged previews, and doctor warnings |
| `1` | Operation failure or a completed doctor report containing an error check |
| `64` | Invalid usage, including unknown commands, options, or invalid option combinations |

Unknown commands and subcommands report `Unknown command '<name>'` and exit
64 even when `--help` or `-h` comes before or after the unknown name. Both
`agents unknown --help` and `agents skills --help unknown` are usage errors.
Command-path validation stops at `--`; leaf command positionals remain arguments.

Doctor's `ok` means there are no error checks; warnings do not make it false.
Instruction `invalidTarget`, `conflict`, `invalidConfiguration`, and
`stateUnavailable` diagnostics and both pending-recovery findings are errors.
Other instruction diagnostics, including drift and missing blocks, are
warnings. Other skill severities are supplied by core.
A failed operation emits no successful JSON report. JSON stdout contains only
one object and a trailing newline; recovery notices remain on stderr.

## JSON Schemas

All reports have integer `schemaVersion: 1`. Object keys are sorted. Arrays
follow core's deterministic ordering; instruction section lists preserve
selection order, targets and prompt names are sorted, and doctor roots retain
input order.
Optional properties are omitted when unavailable. Instruction target
`beforeAgents` is always present and is `null` when no previous lock entry exists.
Filesystem paths, including update file `path` fields, are absolute except
instruction section `path` (source-relative), `target` keys (project-relative,
`~`-relative for user targets under HOME, otherwise absolute), and prompt
`append` paths (scope-root-relative). Watch item `oldPath` and `newPath` are
relative to the source search root (`--path` when present); watch diff file
`path` is item-relative. File bytes use standard base64. Missing
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
| `watch status --json`, `watch --json` | [Watch status](Schemas/watch-status.schema.json) | `schemaVersion`, `scope`, `sources` |
| `watch diff --json` | [Watch diff](Schemas/watch-diff.schema.json) | `schemaVersion`, `scope`, `source` |
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
  `changed` (file bytes differ), `agentsChanged` (recipients differ),
  `beforeAgents` (previous agent IDs, or `null` when no lock entry existed),
  `afterAgents` (planned agent IDs, empty when no longer managed), optional
  `before`/`after` file snapshots, optional `drift`, `adoptedSections`, and
  `conflicts` with existing/proposed text and difference. Agent IDs use their
  raw values in deterministic order.
- `changedPrompts`: prompt names whose content definition changed.
- `lockMissing`: no scope lock existed when the operation began.
- `changed`: applying changes the declaration, locked state, or target bytes,
  including recipient-only changes with identical file bytes and targets that
  need a missing lock recorded.

Instruction file snapshots use the same `{ "kind": "file", "base64": "…" }`
shape as skill files. `install --json` reports restored skill rows and
instruction restoration differences; instruction `sections` and
`changedPrompts` are empty because install never resolves new content.
The definitions are CLI-owned and do not expose core's encoded lock objects.

Watch `sources` entries (and the single diff `source` object) include `alias`,
normalized `source`, `seen`, `current`, optional Git `commitCount`, and `changes`.
Each baseline is either `{ "revision": "<full commit ID>" }` or
`{ "artifacts": { "<name>": "sha256:…" } }`. Changes include `name`,
`kind: "skill" | "instructions" | "artifact"`,
`change: "new" | "changed" | "removed"`, `fileCount`, and available
`oldPath`, `newPath`, `oldDigest`, and `newDigest`. Diff adds `files` with
`path` and optional `before`/`after` snapshots; regular files include
`kind: "file"`, `base64`, and boolean `executable`. Directory and symlink
entries use the same shapes as update previews. Status omits file snapshots.
Artifact digests may change with zero file differences; `fileCount` remains zero.
