# Training MCP v1 field boundary (LYB-279)

Decision: **No** physique, recovery narrative, body composition, GLP-1 or other
medication, pain notes, or location may be read or written by v1 training MCP
plan, set, check-in, or progress operations. Training permission does not grant
access to those categories. There is no opt-in extension in v1.

The sole executable allowlist is
[`TRAINING_MCP_V1_ALLOWLIST`](../../apps/web/src/lib/mcp/training-field-allowlist.ts).
Its strict nested schemas define the data payloads for these operations:

| Operation       | Allowed data                                                                                                                             |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| `read_plan`     | Session reference and engine-returned exercise prescriptions, including catalogue name, rep range, target load, and opaque evidence IDs. |
| `log_set`       | Session/exercise references, set ordinal, reps, external load in kg (nullable for bodyweight), RIR, and optional completion time.        |
| `log_check_in`  | `completed: boolean` only. Completion does not establish recovery, readiness, absence of pain, or clinical clearance.                    |
| `read_progress` | Set logs, last-used external load per exercise, and a non-clinical check-in completion flag.                                             |

Unknown fields are rejected at every nesting level, including fields inside
arrays. No free-form notes, generic metadata, raw record spreads, or opaque
objects are allowed. Catalogue names and engine evidence identifiers are not
user narrative fields. An allowed key cannot be used to smuggle excluded data.
The schemas apply to read results, write inputs, and write readback data. Empty
read arguments and transport/auth/error envelopes are outside these data schemas;
they must never carry excluded user data.

This slice locks a contract for future v1 consumers. It does not change the
existing broader MCP tools, native recovery feedback, or historical progress API;
those payloads must not be passed through as v1 data. The v1 server, Jovie issuer,
and on-device chat remain outside this slice (LYB-72). Set identity/offline
durability remain on LYB-123; progress calculations and last-used load behavior
remain on LYB-37. Numeric prescriptions still belong to the deterministic engine.

`training-field-allowlist.node.test.ts` runs in the existing required web test
suite. It checks the exact operation/field keys, rejects forbidden and unknown
payload fields, and scans production source definitions for a missing or second
allowlist. Tests and fixtures may describe expected or invalid contracts; product
code must import the canonical definition instead of copying it.
