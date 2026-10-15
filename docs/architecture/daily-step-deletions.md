# Daily step deletion compatibility

This backend capability removes a daily step measurement while retaining notes,
the original record date and unrelated JSON fields. It is the first stage of the
native Steps History repair. It does not enable or qualify the native action.

## Activation and retention

`DELETE /api/auth/mobile/sync/v1/daily-metrics` accepts a new body containing only
`step_deletions`, an array of 1–100 distinct record IDs. Creation requires the
injected server capability, whose default implementation reads the exact value
`LYB_STEPS_HISTORY_DELETE_V1_ENABLED=true`. This is a deployment availability
control, not a server Statsig reader. Native activation will separately use the
default-off `steps_history_delete_v1` AnalyticsPort/Statsig gate.

Off, unavailable or missing typed storage returns HTTP 409
`steps_deletion_unavailable`; it never falls back to another entity or a generic
whole-record deletion. Existing `{ ids: [...] }` operations remain compatible.
No environment or native gate is enabled by this change.

Retention is unconditional. Once saved, the marker is honored by ordinary daily
POST and returned by ordinary pull/export regardless of the creation gate. A
future explicit restore contract is separate; automatic imports cannot clear it.
Account deletion still removes the owner's records and markers.

## Captured day and payload

Each deletion contains `record` (its original UUID/date and non-step snapshot),
`day_start`, `day_end`, and `time_zone`. Bounds must describe one complete local
calendar date in the named time zone, with the record inside the half-open
interval. Strict timestamps, actual local-date boundaries and continuity are
checked; duration alone is insufficient. DST, midnight transitions and skipped
calendar dates are supported, with an additional 48-hour safety bound. Month/year
intervals, partial days, duplicate IDs and records outside the day are rejected.

The native caller must capture its existing Calendar start-of-day and next-day
bounds at confirmation. The server retains these absolute instants and the
original record date. Later travel does not reinterpret or widen the saved
interval. Equivalent-offset representations of the same bounds are idempotent.

The server stores `steps: null`, `steps_present: false`, and reserved
`steps_deletion` metadata: `schema_version: 1`, server `deleted_at`, `day_start`,
`day_end`, and `time_zone`. This is a field-specific marker, not whole-row
`deleted_at`; other daily fields remain available. A never-uploaded owned record
can create the marker using its captured non-step snapshot. Existing server
notes/unknown fields are retained during deletion. Client-supplied marker,
owner and server timestamp metadata are ignored.

All owned rows inside the saved interval lose only their step measurement.
Subsequent same-ID or different-ID daily upserts inherit the marker. Same-ID
stale replay cannot move the original marker/date or omit stored non-step
fields. Explicit subsequent non-step updates can replace their submitted keys;
omitted keys survive. Non-marked records retain existing replacement semantics,
including the established legacy `steps_present` and DEXA compatibility rules.

## Transaction and sync contract

Typed deletion and admitted daily POST both use the existing captured account
incarnation and `app_users FOR UPDATE` admission guard as the first transaction
statement. Marker lookup occurs after this guard, in a later statement, so it
sees the preceding same-owner commit even when the competing record UUID differs.
The deletion's anchor and same-day updates commit atomically. Foreign UUID
collisions reject that anchor and cannot authorize another owner's day.

The response returns saved records (including affected siblings) and
`rejected_ids`; clients must not treat a rejected anchor as success. A future
native revision-aware acknowledgement must not mark later local note edits as
synced. Native migration, local admission, import exclusion, marker pull merge,
retry/refresh and actual History routing remain subsequent qualification stages.

Validation uses route/adapter/calendar tests plus actual adapter SQL in a
disposable PostgreSQL 16 cluster. The race harness observes both lock schedules
with different UUIDs and actual blocking PIDs. It never connects to hosted data.
