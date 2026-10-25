# Reviewed training cycles (LYB-115)

New native enrollment previews and explicitly applies a 4-, 5-, or 6-week cycle through
`/api/auth/mobile/training/v1/program-proposals`. The existing default-off
`hypertrophy_coach_v1` platform gate and `LYB_HYPERTROPHY_COACH_API_ENABLED` server
flag still control access. No MCP endpoint, tool, approval label, or rollout setting
changes. PR #1210 is merged; its shared logging/service path remains canonical.

The engine's conservative RIR policies are `[4,3,2,5]`, `[4,3,3,2,5]`, and
`[4,4,3,3,2,5]`, respectively. These are versioned application programming choices,
not claims of a physiologically optimal duration. The final week reduces baseline
sets from two to one and holds progression. Existing evidence-tagged reactive
recovery reductions and pain pauses remain in force, including during deload.

A configured block has a stable identity. Its current week requires both the
calendar opportunity and all slots in preceding weeks to be completed. Missed
weeks, skipped attempts, and early-ended incomplete sessions never fill those
slots. A retry after an ended attempt has a new session identity; accepted set logs
stay on the original attempt. Active and paused workouts retain their saved targets
across calendar rollover. Final deload completion enters review, with no automatic
block rollover. Drafts record the transition to adjustment or next block; the live
service reports accumulation, planned/reactive deload, or review explicitly.

`revise_cycle` previews shortening or extension against the current revision.
Active attempts move to the accepted revision atomically while retaining their saved
prescriptions and accepted sets. A revision cannot reinterpret
trained weeks as a new final deload or extend a deload that was already attempted.
Apply uses the same atomic revision decision as initial enrollment. Profile,
consent, revision, policy, calendar-preview, or training changes require refreshed
review. The database checks the training fingerprint under its existing owner lock;
revision, setup, head and receipt commit together. Historical sessions are untouched.

`repeat_cycle` is available at review. It builds a draft with explicitly selected
observed variant IDs and their reasons, retaining variant-specific progression and
links to the original sessions, logs, and feedback. Planned deload logs remain
visible history; progression uses completed accumulation work rather than treating
the reduced deload work as overload evidence. It never copies another
exercise's loads or relabels observations. Temporary priorities and constraints
expire at the boundary; the draft renews them only when requested. Equipment and
enduring variant exclusions remain separate. Unknown, incompatible, unavailable,
or excluded reuse variants fail closed. Native presents the engine preview before
Apply and supports explicit rejection.

Old setups without `cycle` retain their existing calendar policy until a reviewed
revision opts them in. The legacy enrollment endpoint remains compatible.

Apply `20261025030000_training_cycle_lifecycle.sql` before deploying the adapter.
This change does not apply production migrations, enable flags, or enroll users.
Missing atomic storage fails closed. Native shipping still requires exact-commit
Xcode, coverage, UI, and installed-build receipts from the real macOS runner.

Local verification:

- `pnpm lint`, `pnpm typecheck`, and `pnpm test` use existing workspace tasks.
- The lifecycle engine/service/revision fixtures and authenticated route fixtures
  run in the existing web Jest suite.
- `python3 apps/web/db/tests/verify-training-revisions.py --docker-image postgres:16`
  runs real synthetic transactions and lock-order races in a disposable container
  with no network or published ports. `--postgres-bin` remains supported. This
  verifier covers existing enrollment/revocation/isolation controls as well as
  cycle revisions, competing heads, stale training, rollback and next-block reuse.
- Native request/receipt and review-state decoding regressions are in the existing
  `ChatServiceTests` target. UI length/reuse fixtures use the same review view and
  preserve the existing Close hit-target test. New Swift files have explicit app
  target membership.

Host qualification on 2026-10-25: root lint and typecheck passed; the full web
`test:ci` script passed 123 suites / 1,158 Jest cases plus three voice-adapter cases.
The focused training/route/adapter run passed 205 cases. Disposable PostgreSQL 16
passed 23 transaction checks. The lifecycle fixture failed with the original
engine, and the stale-training transaction fixture failed when only its freshness
guard was removed. SwiftLint found zero violations in available rules; five
SourceKit-dependent rules were unavailable. `xcodebuild` is absent on this Linux
host, so native execution, coverage and installed-build UI evidence are unverified.
GBrain search, write and same-slug readback all failed to connect to the local
service at `127.0.0.1:7801`; no persisted knowledge write is claimed.

The root `pnpm test` retry built successfully and passed 1,157 web cases, but its
existing canvas replay test exceeded the five-second timeout. That test passed in
the full serial web run; no timeout or gate was changed.
