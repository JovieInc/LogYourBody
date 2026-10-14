# Immutable Jovie UI consumer

This is a source-pinned distribution subset of Jovie's actual `@jovie/ui` Button,
Input, Button contract, Spinner and utility dependency graph. It is not a LYB-owned
control implementation. `source.json` identifies the upstream repository,
immutable revision, file paths and SHA-256 bytes. Do not hand-edit these files.

Marketing imports `@jovie/ui/atoms/button` and `@jovie/ui/atoms/input` directly.
Legacy, deferred web-app consumers remain outside this marketing migration.
The exact dependency versions already used by LYB are resolved in its frozen
workspace lockfile; no external service or credential is introduced.

Updates must be made in the Jovie owner, reviewed there, then imported unchanged
with the receipt. `shared-controls.node.test.ts` fails on byte drift and tests
projection parity for the matching canonical tokens. When a versioned published
Jovie UI distribution exists, consume it and retire this materialized subset.

The marketing Input intentionally requests a 44px form box with 16px type for
mobile input compatibility. The canonical Button uses the upstream 28px visible
face and 44px invisible hit target; no hover transform or custom variant is added.
The upstream Pen identity is carried only for mapped variant/size combinations;
this consumer does not fabricate Pen parity or claim native save/readback.
