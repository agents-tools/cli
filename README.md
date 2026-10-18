# agents

`agents` manages agent skills from declared sources. Add skills once, restore
their exact locked content with `install`, and preview upstream changes before
applying an update. It supports Codex, Claude Code, Cursor, Gemini CLI, and
OpenCode through [agents-tools/core](https://github.com/agents-tools/core).

The executable owns commands and terminal presentation. Core owns source
resolution, declarations, locks, discovery, installation, and recovery.

## Build and Run

Requires macOS 13 or later and Swift 6.3 or later. Build from source:

```sh
git clone https://github.com/agents-tools/cli.git
cd cli
swift build -c release
.build/release/agents --help
```

The examples below use `agents` as the executable name; from this checkout,
use `.build/release/agents` or `swift run agents`.

```sh
agents skills add https://github.com/anthropics/skills.git --all --agent codex
agents skills list
agents skills list --scope user --json
agents install
agents update
agents update --apply
agents skills remove pdf
agents skills init my-skill
agents doctor --root /path/to/project-a /path/to/project-b --json
```

Project scope is the default and uses the current directory. User scope is
selected with `--scope user`. Commands never prompt for confirmation.
See the [CLI reference](Documentation/Reference/CLI.md) for options, state
locations, JSON schemas, and exit codes.

## Development

```sh
swift build
env -u CODEX_HOME -u CLAUDE_CONFIG_DIR -u XDG_CONFIG_HOME -u XDG_STATE_HOME -u XDG_CACHE_HOME swift test
swift build -c release
xcrun swift-format lint --strict --configuration .swift-format --recursive Package.swift Sources Tests
git diff --check origin/master
```

Executable tests create local Git sources and isolated homes in the system
temporary directory. Every child process uses an explicit environment rather
than inheriting agent or Git configuration. Fixtures are removed after tests.

Core follows `master` during development. To use a local core worktree without
changing the package manifest:

```sh
swift package resolve
swift package edit core --path /path/to/core-worktree
swift test
swift package unedit core
```

Keep the local edit inside your authorized development scope. Releases switch
to a version range according to core's
[release checklist](https://github.com/agents-tools/core/blob/master/Documentation/Reference/Release.md).
The CLI version is defined once in `Sources/CLI/EntryPoint.swift`.

[Documentation](Documentation/README.md) indexes the command reference and schemas.
