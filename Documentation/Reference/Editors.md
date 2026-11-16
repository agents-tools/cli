# YAML Editor Setup

`agents manifest schema` exports the bundled schema offline. Standard YAML
completion, hover and structural validation use this same schema; saved-file
scalar, tag and domain diagnostics come from an explicit `agents manifest check`.
The checker does not inspect an unsaved editor buffer. Save and rerun the task
after each edit; old task results describe the last checked saved file.

The examples below are workspace settings and process tasks for Cursor or VS
Code with Red Hat YAML. Actual editor/version verification is separate from CLI
validation. Choose your project root explicitly. Do not write these examples to
user-wide settings automatically.

## Export and Associate the Schema

Choose a local destination and re-export after upgrading the CLI:

```sh
mkdir -p "$HOME/.local/share/agents"
agents manifest schema > "$HOME/.local/share/agents/agents.schema.json"
```

The schema is distributed with the executable; its `$id` is an identity, not an
instruction to download it. Replace the example absolute file URI below with
your exported file. In the selected project's `.vscode/settings.json`:

```json
{
  "yaml.yamlVersion": "1.2",
  "yaml.schemaStore.enable": false,
  "yaml.validate": true,
  "yaml.completion": true,
  "yaml.hover": true,
  "yaml.format.enable": false,
  "editor.formatOnSave": false,
  "yaml.schemas": {
    "file:///Users/alice/.local/share/agents/agents.schema.json": [
      "/.agent/agents.yaml"
    ]
  }
}
```

Associate only the canonical declaration. For user scope, open the chosen
`~/.agents` directory as its own workspace and use `["/agents.yaml"]` for that
association. `agents.resolved` is tool-owned JSON and is not a declaration.

The standard YAML schema provides field descriptions, examples, required fields,
union shapes and enums. It does not establish Core's exact scalar or domain
semantics: for example, mathematical JSON Schema integers cannot distinguish
`1` from `1.0`. Core also checks duplicate keys, allowed tags, integer bounds,
exact native decimal text, and references. Keep `!!float` values as authored;
do not add blanket custom tag allowances or auto-format/re-serialize them.

## Check the Saved Declaration

In that project's `.vscode/tasks.json`:

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Check agents declaration",
      "type": "process",
      "command": "agents",
      "args": ["manifest", "check", "--scope", "project"],
      "options": {"cwd": "${workspaceFolder}"},
      "problemMatcher": {
        "owner": "agents-manifest",
        "source": "agents",
        "fileLocation": "absolute",
        "pattern": {
          "regexp": "^(/.*):([0-9]+): (error|warning|info) \\[([^\\]]+)\\]: (.*)$",
          "file": 1,
          "line": 2,
          "severity": 3,
          "code": 4,
          "message": 5
        }
      }
    }
  ]
}
```

Run this task explicitly after saving. It reads `${workspaceFolder}/.agent/agents.yaml`;
it does not search parent directories or infer scope from the active tab. For a
multi-root workspace, select a root and give its task an explicit cwd.

For the user-scope workspace, change the args to
`["manifest", "check", "--scope", "user"]` and use explicit task options such as:

```json
{
  "cwd": "${workspaceFolder}",
  "env": {"HOME": "/Users/alice"}
}
```

Replace `/Users/alice` with the intended home; user scope reads
`HOME/.agents/agents.yaml`, independently of cwd. It does not mean the workspace
folder is HOME. For isolated editor verification, use the isolated fixture home.

The matcher links absolute paths and **lines only**. UTF-8 byte columns remain
in the message; they are not editor character columns. Related locations are
separate `info` lines carrying the original diagnostic code. Control characters
and line separators in messages are escaped. An unrepresentable path is shown
as `Diagnostic at … (line …)` and deliberately does not match a clickable file.
Scope, missing-file, recovery and I/O failures remain ordinary nonzero command
failures in the task terminal; they are not fabricated source diagnostics.

No task applies fixes, runs recovery, resolves sources, reads secrets or executes
components. Success with warnings exits 0, a command or manifest error exits 1,
and invalid arguments exit 64. A clean declaration prints nothing. Check the
saved declaration again with `agents manifest dump --json` when you need Core's
complete readback; the checker itself does not print configuration values.

## Distribution

An installed `agents manifest schema` needs SwiftPM's AgentsManifest resource
bundle with the executable. Copying the executable alone is insufficient. The
verified macOS layout places the actual executable and
`core_AgentsManifest.bundle` together in `libexec`, with a `bin/agents` exec
launcher that invokes that real executable path. A binary symlink alone keeps
Foundation's bundle lookup under `bin` on the tested macOS runtime.

The existing Homebrew formula installs only the executable; its schema-export
packaging update must be delivered and verified by the tap owner. Use a source
build with its resources until that update is available. The CLI does not
substitute an embedded second schema or fall back to a network service.
