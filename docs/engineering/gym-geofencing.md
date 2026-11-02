# Implementation slice: opt-in gym geofencing

Parent: LYB-175.
Decision dependency: [LYB-250: gym-detection consent](../architecture/gym-detection-consent.md).
Implementation dependency: attendance-states slice.
Status: repository slice created; external tracker publication/ID is pending.

## Scope

Implement per-gym native iOS detection using the LYB-250 data, copy, retention and
erasure contract. Send only `probable` attendance evidence to the attendance-state
owner; use its canonical model rather than creating a parallel attendance system.
Do not begin implementation until that dependency's interface is available.

Use a default-off Statsig gate through the existing Platform port. Isolate Core
Location behind a Platform port/adapter and keep persistence and derived-data
work off the main actor. Use Core Data as the local source of truth. No cloud
location schema, location sync, or new external service is authorized.

## Acceptance

- [ ] Use the exact LYB-250 disclosure and per-gym opt-in, followed by contextual
      OS authorization. Existing OS permission never substitutes for gym consent.
- [ ] A denied, downgraded or revoked permission leaves the rest of LYB usable
      and cannot automatically resume detection after authorization returns.
- [ ] Persist only the allowed gym configuration and probable-event fields;
      exclude them from backups, telemetry, model context and cloud sync.
- [ ] Events expire exactly 14 × 24 hours after detection, are unavailable at
      expiry, and are purged on the next execution before use. No retained derived
      location history or reset of the deadline on replay/timezone changes.
- [ ] Implement per-gym revoke/removal, one-tap delete all, sign-out and account
      deletion, including cached evidence and pending callbacks/writes. Deletion
      failures stop detection and offer the LYB-250 retry copy without false success.
- [ ] Keep erasure and expiry working with the feature gate off; fresh opt-in
      after deletion cannot resurrect events. Accounts and devices remain isolated.
- [ ] Deliver only probable evidence; never manufacture a workout, timestamps
      claimed as user-confirmed, duration, sets, fatigue or adherence from location.
- [ ] Update the shared/bundled privacy disclosure and review App Store privacy
      inventory and usage descriptions before collection can be enabled. Include
      the repository's required privacy and native validation receipts.

## Verification

Add native behavior tests for consent for two gyms, existing OS permission without
consent, denial/revocation/downgrade and restoration, gate shutdown, account
switching, gym removal, one-tap delete all and deletion failure/retry. Prove that a
late callback or in-flight write cannot restore deleted data after revoke,
delete, sign-out or re-opt-in.

Use an injected clock for just-before/exactly-at/after expiry, replay and timezone
changes, and relaunch after the app was suspended past expiry. Inspect persisted
fields and backup exclusion, and verify no raw location or attendance evidence
enters logs, analytics, model context or network requests. Run the repository's
real native runner for current-head execution and coverage; source checks alone
are not native proof. Real-device TestFlight evidence remains with LYB-175.

## Out of scope

Attendance-state design, workout reconciliation, fatigue/scheduling adaptation,
training prescriptions, set logging, continuous location tracking, cloud sync and
other LYB-175 work. This slice does not authorize broader location use.
