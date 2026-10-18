# cli Agent Guide

Read `README.md` for purpose, usage, and development commands, then
`Documentation/README.md` for documentation placement.

## Ownership

- Keep command parsing, terminal output, exit codes, and JSON schemas here.
- Keep source resolution, declarations, locks, recovery, discovery, and skill
  lifecycle behavior in `agents-tools/core`. Use its public APIs.
- `Documentation/Reference/CLI.md` describes the shipped command contract.
- `Package.swift` owns the package graph; `Package.resolved` pins development
  dependencies; `Sources/CLI/EntryPoint.swift` owns the executable version.

## Working Conventions

- Work and commit only in the task's worktree. Use Conventional Commits and
  the repository's local signing configuration. Push and merge require the
  user's authorization.
- Do not embed machine-specific paths or execution state in reusable files.
- Keep CLI schema types independent of core's encoded representations.
- Run executable tests with an isolated HOME and an allowlisted environment.
  Never inherit agent configuration, XDG variables, or Git configuration.
  Create Git fixtures with an explicit initial branch and remove all fixtures.
- Keep temporary task reports in ignored `.agent/`; SwiftPM owns `.build/`.
- Run the build, test, release build, strict format lint, and diff checks from
  the README before handing off behavior changes.
