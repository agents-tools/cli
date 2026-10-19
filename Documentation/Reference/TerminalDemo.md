# Terminal Demo

## Recording the README demo

From the repository root, build the release executable and run the recorder:

```sh
swift build -c release
python3 Documentation/Assets/Demo/record.py
```

The recorder creates a local Git source and project under an isolated HOME in
`.agent/readme-demo/home`. It uses an allowlisted environment, disables inherited
Git configuration, and allows only Git's local file transport. Fixed fixture
content, identity, dates, and initial branch reproduce the fixture revisions.
After installing `pdf` and adding `code-review` and `commits`, it watches the
source, edits the review instruction to require tests, commits that edit, and
runs `agents watch` followed by `agents update --apply`. It verifies the installed
skill and resulting instructions, then removes the fixture, including its HOME.

The [recording](../Assets/Demo/record.json) contains successful commands and their
output. [Provenance](../Assets/Demo/provenance.json) records the source revision,
release executable version and digest, toolchain, pinned dependencies, fixture
inputs and revisions, exit codes, and output normalization. HOME paths become
`~`; one final newline is removed from each stdout for renderer spacing. The
private `.agent/readme-demo/receipt.json` retains the exact environment, raw
stdout, stderr, and replacement counts for local verification. Keep this ignored
receipt with the recording evidence; do not publish its private paths.

Re-render both themes with the `github-repo-steward` helper, then check them:

```sh
python3 ~/.claude/skills/github-repo-steward/scripts/render_terminal.py \
  --record Documentation/Assets/Demo/record.json \
  --spec Documentation/Assets/Demo/recipe.json \
  --output-dir Documentation/Assets/Demo
python3 ~/.claude/skills/github-repo-steward/scripts/render_terminal.py \
  --record Documentation/Assets/Demo/record.json \
  --spec Documentation/Assets/Demo/recipe.json \
  --output-dir Documentation/Assets/Demo --check
```

The [recipe](../Assets/Demo/recipe.json) copies the font and light/dark colors
from the organization's
[DESIGN](https://github.com/agents-tools/.github/blob/master/DESIGN.md#presentation)
and records its revision and digest. Terminal dimensions use the renderer's
documented defaults because that DESIGN revision does not specify them. Review
the pinned DESIGN when changing tokens; the renderer does not fetch or check it.
Inspect both SVGs in a browser before committing the inputs and exports together.
