# CLI Reference

`agents` manages declared skills. All resolution, installation, state, and
recovery operations use `AgentsCore` and `AgentsSkills`.

## Commands

```text
agents skills add <source> [names…] [--all]
agents skills list [source] [--json]
agents skills remove <names…>
agents skills update [names…] [--apply | --json]
agents skills init [name]
agents install
agents update [--apply | --json]
agents doctor [--root <dir>…] [--json]
```

`agents --help`, `agents skills --help`, and each command's `--help` describe
their options. Running a group without a subcommand prints help. `--version`
prints `agents X.Y.Z`; the version constant lives in `Sources/CLI/EntryPoint.swift`.

## Shared Options

| Option | Meaning | Commands |
| --- | --- | --- |
| `--scope project\|user` | Choose declaration and lock scope; default `project` | All lifecycle and read commands; `init` uses the current directory |
| `--agent <agent>` | Choose recipients; repeat the option for several | `skills add`, `skills list`, `skills remove`, `doctor` |
| `--path <subdir>` | Search inside a source-relative subdirectory | `skills add`, `skills list <source>` |
| `--full-depth` | Discover recursively beyond conventional skill directories | `skills add`, `skills list <source>` |
| `--mode link\|copy\|edit` | Choose installation materialization; default `link` | `skills add` |
| `--json` | Emit a versioned JSON report on stdout | `skills list`, `doctor`, both update previews |

Agents are `codex`, `claude-code`, `cursor`, `gemini-cli`, and `opencode`.
Core also accepts `claude` and `gemini` as input aliases. Output uses canonical
IDs. On add, omitted recipients use declaration defaults (initially Codex and
Claude Code). On installed list, remove, and doctor, omission covers all
recipients. Source listing shows available skills regardless of recipients.
Doctor's agent filter limits installation checks; source checks cover the scope.

Updates use declared paths, recipients, and modes. Installation restores those
recorded in the lock. Neither update nor install accepts a recipient or mode
override. `--path` always refers to source discovery, never a project root;
change directory for project operations or use doctor's `--root` for auditing.
Unsupported options are usage errors.

## Adding and Inspecting Sources

`source` is a local path, Git URL or shorthand accepted by core, well-known
HTTP source, or an existing declaration alias. Add writes the declaration,
installations, and lock together. No names selects a sole discovered skill;
multiple discovered skills are listed with selection guidance and are not
installed. Explicit names select those skills. `--all` selects all current and
future members on unnamed updates; combining names and `--all` is a usage error.

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

## Update, Restore, Remove, and Initialize

Both update commands preview by default, comparing newly resolved declarations
against disk. `skills update <names…>` limits resolution to named skills;
`agents update` and unnamed `skills update` reconcile every declared skill,
including membership changes in `all` selections.

`--apply` prints old/new revisions, hashes, and full before/after file snapshots
before core replaces targets and lock together. File output includes deletion,
directory, symbolic-link destination, text, and binary bytes (base64). This is
a full snapshot comparison, not a minimal unified patch. A preview can become
stale; `--apply` resolves again and displays the content it will actually write.
`--json --apply` is a usage error.

`install` restores exact locked pins, hashes, modes, and recipients. It does not
resolve newer versions and takes no source argument. Unavailable pins or content
that fails digest verification cause failure.

`remove` requires names and removes their declarations, files, and lock entries.
With `--agent`, it removes only those recipients. Removing a member of an `all`
selection records an exclusion so an update does not reinstall it.

`init [name]` creates a skill directory and `SKILL.md` in the current directory;
without a name it creates `SKILL.md` directly there. Existing files are errors.

## Doctor and State

Doctor reports core's skill checks, including missing installations, drift,
broken links, newer matching source revisions, and uncommitted source content.
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

| Code | Meaning |
| --- | --- |
| `0` | Success, including help/version, unchanged previews, and doctor warnings |
| `1` | Operation failure or a completed doctor report containing an error check |
| `64` | Invalid usage, including unknown commands, options, or invalid option combinations |

Doctor's `ok` means there are no error checks; warnings do not make it false.
A failed operation emits no successful JSON report. JSON stdout contains only
one object and a trailing newline; recovery notices remain on stderr.

## JSON Schemas

All reports have integer `schemaVersion: 1`. Object keys are sorted. Arrays
follow core's deterministic skill ordering; doctor roots retain input order.
Optional properties are omitted when unavailable, never encoded as `null`.
Filesystem paths, including update file paths, are absolute. File bytes use standard base64. Missing `before` or `after`
means that entry is absent, distinct from an empty file or directory.
Clients should ignore unknown properties; incompatible changes require a new
schema version. Diagnostic IDs are core-defined strings, not a closed enum.

| Command | Schema | Required root fields |
| --- | --- | --- |
| `skills list --json` | [Installed list](Schemas/installed-list.schema.json) | `schemaVersion`, `kind: "installed"`, `scope`, `skills` |
| `skills list <source> --json` | [Source list](Schemas/source-list.schema.json) | `schemaVersion`, `kind: "source"`, `scope`, `source`, `skills` |
| `update --json`, `skills update --json` | [Update](Schemas/update.schema.json) | `schemaVersion`, `scope`, `changed`, `skills` |
| `doctor --json` | [Doctor](Schemas/doctor.schema.json) | `schemaVersion`, `ok`, `roots` |

An empty installed list:

```json
{"schemaVersion":1,"kind":"installed","scope":"project","skills":[]}
```

An empty update preview:

```json
{"schemaVersion":1,"scope":"project","changed":false,"skills":[]}
```

A healthy doctor report:

```json
{"schemaVersion":1,"ok":true,"roots":[{"root":"/project","scope":"project","ok":true,"checks":[]}]}
```
