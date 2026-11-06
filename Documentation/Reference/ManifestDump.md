# Manifest Dump Contract

`agents manifest dump --json [--scope project|user]` exposes the manifest
language's evaluated JSON schema. The authoritative schema and byte contract
are core's [Evaluated JSON Dump](https://github.com/agents-tools/core/blob/a2d734fb14cf2d93e7ddd8a6087d7c90453abea4/Documentation/Reference/Manifest.md#evaluated-json-dump),
including its construction vocabulary and evolution rules. The CLI prints
`ManifestDump.encodedJSON()` bytes unchanged; it does not define another
semantic representation or wrap the result in a CLI report.

The current object identifies `schemaVersion: 1`, `kind: "manifest"` and
`languageVersion: "1.0"`. It contains `sourceDigest`, `declaration`, `locations`
and `diagnostics`. These fields, their normalized values, discriminants,
ordering and defaults are owned by the linked language contract. Locations
use the stable document identity `manifest`, with UTF-8 byte offsets and
1-based line/byte-column coordinates. The source digest covers original bytes,
so comments can change digest and locations while declaration values stay equal.

Output is one UTF-8 object with sorted keys, two-space indentation and a trailing
LF. It includes symbolic conditions and group references; secrets and runtime
environment references remain symbolic. Readers ignore unknown object keys and
reject unsupported schema versions or unknown semantic discriminants.

The selected path and scope determine the input and are not extra JSON fields.
A failure emits no partial JSON. The CLI owns argument validation, error
presentation and exit codes, documented in [CLI Reference](CLI.md#manifest).
Other [CLI JSON schemas](CLI.md#json-schemas) describe independent report shapes;
they do not describe declaration storage or this language object.
