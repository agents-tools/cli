---
description: Keep the agents CLI a command layer over core, with its own schemas, contract document and verified CI contexts.
---
# cli Agent Guide

## Ownership

- Keep command parsing, terminal output, exit codes and JSON schemas here, and
  keep CLI schema types independent of core's encoded representations.
- Keep source resolution, declarations, locks, recovery, discovery and skill
  lifecycle behavior in agents-tools/core; use its public APIs.
- Update `Documentation/Reference/CLI.md`, the shipped command contract, with
  every command change. The executable version lives in
  `Sources/CLI/EntryPoint.swift`.

## Workflows and Assets

- For workflow changes, run `actionlint` on every workflow. Verify the required
  checks on a real candidate run before changing required-check settings.
- The demo job re-records `recording.json` and uploads it on drift. Render and
  check terminal SVGs and the social preview locally with the
  github-readme-design toolchain against `agents-tools/.github`'s DESIGN, fonts
  and catalog.
