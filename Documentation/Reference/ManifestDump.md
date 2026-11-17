# Manifest Dump Contract

`agents manifest dump --json [--scope project|user]` exposes the manifest
format's JSON contract. The authoritative schema and byte contract
are core's [Bounds and Dump](https://github.com/agents-tools/core/blob/25187e040ca0dd98e96c48704a4a7e95d4da198c/Documentation/Reference/Manifest.md#bounds-and-dump),
including its semantic records and evolution rules. The CLI prints
`ManifestDump.encodedJSON()` bytes unchanged; it does not define another
semantic representation or wrap the result in a CLI report.

The current object identifies `schemaVersion: 2`, `kind: "manifest"`,
`format: "yaml"` and `manifestVersion: 1`. It contains `sourceDigest`,
`declaration`, `locations` and `diagnostics`. These fields, their normalized
values, discriminants, ordering and defaults are owned by the linked manifest
contract. Locations
use the stable document identity `manifest`, with half-open UTF-8 byte offsets
and 1-based line/UTF-8-byte-column coordinates in the original YAML bytes. The
source digest covers original bytes, so comments can change digest and locations while declaration values stay equal.

Output is one UTF-8 object with sorted keys, two-space indentation and a trailing
LF. It includes symbolic conditions and group references; secrets and runtime
environment references remain symbolic. Readers ignore unknown object keys and
reject unsupported schema versions or unknown semantic discriminants.

The selected path and scope determine the input and are not extra JSON fields.
A failure emits no partial JSON. The CLI owns argument validation, error
presentation and exit codes, documented in [CLI Reference](CLI.md#manifest).
`NativeValue` records retain their numeric identity: integers have kind
`integer`, while decimals have kind `decimal` and a string `value` preserving
exact decimal text. Semantic location pointers remain indexed, including
`/components/<i>/chatGPT/<j>` for YAML `chatgpt` entries.

Other [CLI JSON schemas](CLI.md#json-schemas) describe independent report shapes;
they do not describe declaration storage or this manifest object.
