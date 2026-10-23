# Terminal Demo

Edit [script.yml](../../.github/assets/terminal/script.yml) to change the
README session's fixture, commands, or expectations. The generated
[recording](../../.github/assets/terminal/recording.json) and
[light](../../.github/assets/terminal/terminal-light.svg) and
[dark](../../.github/assets/terminal/terminal-dark.svg) SVGs live beside it.

## Recording validation

[CI](../../.github/workflows/ci.yml) calls the shared Swift package workflow
with [package configuration](../../.github/swift-package.json). Its `demo`
option selects the `agents` product and uses the default script path,
`.github/assets/terminal/script.yml`.

The `demo` job builds the release executable and re-records the script in its
isolated environment. It compares the fresh recording with the committed
`recording.json` and fails on drift, uploading the regenerated `recording.json`
for review. Download the recording, review the output changes, and place the
accepted recording beside the script before rendering the terminal SVGs locally.
Required checks are exactly `policy / policy` and `validate / result`; the latter
includes the recording check.

## Local rendering and checks

Use the github-readme-design toolchain's
[renderer reference](https://github.com/showxu/skills/blob/master/skills/github-readme-design/references/renderers.md)
for local recording, rendering, and check commands. Run them from a task
worktree and keep temporary inputs under ignored `.build/`.

Render and check terminal SVGs and the
[social preview](../../.github/assets/social-preview/social-preview.png) locally
against [agents-tools/.github](https://github.com/agents-tools/.github)'s
`DESIGN.md`, `.github/design/fonts`, and `profile/catalog.json`. The catalog
entry is `cli`; its light-page icon is this checkout's
`.github/assets/logo/logo.png`. Terminal SVGs outline text in Google Sans Code.

Review both terminal appearances and the social preview. Commit accepted
recording and rendered asset changes with their script or design inputs.
