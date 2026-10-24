# Contributing

Follow the organization's
[contributing guide](https://github.com/agents-tools/.github/blob/master/CONTRIBUTING.md)
and [maintenance change flow](https://github.com/agents-tools/.github/blob/master/MAINTENANCE.md#change-flow).
Use a task worktree, signed Conventional Commits, and the
[development checks](README.md#development). Push and merge require maintainer
authorization.

Build with Swift 6.3 or later on macOS 15 or later. Shared CI compiles and tests
only with Xcode 26.6 on `macos-26`.

Package validation is configured in [.github/swift-package.json](.github/swift-package.json)
and runs through [agents-tools/github-workflows](https://github.com/agents-tools/github-workflows#readme).
Keep shared callers pinned to the same full commit and run `actionlint` on every
workflow after edits. Required checks are exactly `policy / policy` and
`validate / result`. Behavior assertions belong in the package's Swift tests;
executable tests use `CLIFixture` for temporary homes and an allowlisted environment.

The demo job re-records `recording.json` and uploads it on drift. Review the
recording, then render and check terminal SVGs and the social preview locally
with the github-readme-design toolchain against `agents-tools/.github`'s DESIGN,
fonts and catalog. Follow [terminal demo maintenance](Documentation/Reference/TerminalDemo.md)
for the renderer reference and asset locations.
