# Daily step presence on native sync

`POST /api/auth/mobile/sync/v1/daily-metrics` accepts an optional `steps_present`
Boolean alongside the existing `steps` count. This metadata distinguishes an
observed zero from an older client's zero sentinel without changing the stored
count range or adding a SQL column.

| Payload                             | Meaning                                          |
| ----------------------------------- | ------------------------------------------------ |
| `steps: 0, steps_present: true`     | Observed zero.                                   |
| `steps: N, steps_present: true`     | Observed integer from 0 through 2147483647.      |
| `steps: null, steps_present: false` | Explicitly missing.                              |
| No marker, positive valid count     | Legacy positive measurement.                     |
| No marker, zero                     | Ambiguous legacy zero; do not infer observation. |
| No marker, omitted/null count       | Legacy missing measurement.                      |

When a marker is present, it must be a Boolean. `true` requires an explicit
valid count. `false` requires explicit JSON null; omitting `steps` is not enough.
Contradictory or malformed records reject the whole route batch before a write.
The persistence adapter also rejects invalid daily values for internal callers.

A new client forwarding a legacy record must preserve the raw distinction
between unknown provenance and explicit absence. An unmarked numeric zero can
render as unknown, but must upload as numeric zero with the marker omitted.
It must not be rewritten as null plus `false`: that explicitly clears a known
zero which another client may already have recorded under the same identity.
Only a genuinely explicit missing value uploads null plus `false`.

An old-client full-record update can omit the new marker. The daily-only SQL
upsert retains an existing `true` marker only when the authenticated owner,
record ID, exact date string and numeric count are unchanged. Changed count or
date, missing/null count or missing date does not inherit presence. Explicit
`false` plus null clears it. Other fields retain full replacement semantics;
this is not a generic JSON merge. Other collections retain their current
behavior, including the separate DEXA typed-measurement preservation rule.

The original account-incarnation admission capture and transaction guard stay
in place. A matching client-supplied user field cannot authorize another owner.
No existing rows are backfilled, and no unmarked historical zero is upgraded
unless a producer explicitly supplies observed provenance.

Deploy this compatibility behavior before a new native presence writer. Old
clients can still erase presence when they change the measurement itself;
their payload cannot prove whether a new zero was observed. Native storage,
HealthKit observation, migration, reader and export changes remain a separate
dependent implementation. This server change alone does not prove durable
native round-trip or rollout acceptance.

Qualification includes real route and adapter negative cases plus the actual
parameterized upsert in the existing disposable PostgreSQL harness:
`scripts/neon/test-reported-measurements.py`. Existing account-admission and
DEXA controls must remain green. The harness never connects to a live database.
