# Configurable training cycles (LYB-115)

The native coach's existing default-off `hypertrophy_coach_v1` Statsig gate and
server `LYB_HYPERTROPHY_COACH_API_ENABLED` gate protect this surface. There is
no new MCP implementation or web product UI. The existing program-proposals
route and owner-locked revision command own enrollment, length changes and reuse.
Apply `20261025040000_training_cycle_lifecycle.sql` before deploying the adapter.

## Engine and lifecycle

Explicitly configured cycles use `hypertrophy-cycle-v1`. Length includes the
final planned deload:

| Weeks | Weekly target RIR | Baseline sets per exercise |
| ----- | ----------------- | -------------------------- |
| 4     | 4, 3, 2, 5        | 2, 2, 2, 1                 |
| 5     | 4, 3, 3, 2, 5     | 2, 2, 2, 2, 1              |
| 6     | 4, 4, 3, 3, 2, 5  | 2, 2, 2, 2, 2, 1           |

These are bounded engine policies, not claims that a particular cycle length is
optimal for everyone. Deload holds the variant's last load, restarts at the lower
rep target, and never requests an increase. Existing reactive recovery reductions
and pain pauses remain authoritative, including during a planned deload.

The lifecycle distinguishes accumulation, adjustment, planned deload, reactive
deload, review and a proposed next block. Configured progress counts genuinely
completed sessions, not elapsed calendar weeks. Ended, empty, shortened and skipped
attempts are not completed training. Replacement attempts have distinct identities;
the prior prescription and its logs remain intact. An incomplete or paused workout
survives calendar rollover with its own targets and set identities. After the final
week the service returns review and does not automatically enroll the next block.

Legacy setups without cycle configuration retain their calendar-based baseline.
Adopting cycle configuration freezes the current legacy block identity so older
blocks cannot inflate the configured block's completion count.

## Review, revision and reuse

POST `/api/auth/mobile/training/v1/program-proposals` accepts the existing initial
intent with optional `weekCount`, or `revise_cycle` / `repeat_cycle`. Length is a
strict integer union: 4, 5 or 6. The proposal contains an engine-generated schedule,
workout preview, versioned policy, prior setup, actor, reason, assumptions, current
head and training fingerprint. PATCH applies or rejects that exact proposal.
Preview and rejection do not mutate the setup. Profile, training or head changes
invalidate a held draft. Apply checks the current generated preview and schedule.

A length revision preserves completed history and an active workout's prescription.
The SQL transaction changes only the active workout's revision authority, together
with the new setup, immutable revision, head and receipt. It does not rewrite its
sets, week or targets. Shortening cannot remove a deload boundary already entered;
extending cannot turn an already-started deload back into accumulation. Begin a
new block after review in those cases.

Repeat is available only after block review and requires no unfinished workout.
`keepVariants` names the original slot, an actually used variant ID and the user's
reason. Catalog, muscle, equipment, duplicate-slot and enduring exclusion checks
fail closed. Specialty equipment must be explicitly declared; a full-gym preset
does not prove Smith-machine availability. The new setup retains selected variant
IDs, their own completed load history, original feedback records and reasons.
Temporary muscle priorities and constraints are separate cycle context: each
expires unless its explicit renewal flag is true. Equipment declarations and
enduring variant exclusions remain outside that temporary state. This change
does not invent a new priority or constraint dosing algorithm.

Native review displays the returned schedule and workout targets, lets the user
select worked variants and edit their reasons, and offers apply/reject. It does
not calculate prescriptions. Retry identities and account ownership checks prevent
an interrupted response from becoming a second decision or crossing accounts.
The previous setup is retained in the revision ledger; repeat retires its current
setup row while preserving sessions, logs and feedback.

## Verification and release handoff

Deterministic engine/service and authenticated route tests cover every length,
reactive and planned deloads, calendar rollover, skipped/ended attempts, review,
shortening/extension, stale drafts, expiry/renewal and a worked Smith variant with
distinct original-versus-variant load history. Restoring the original engine makes
`planned final deload reduces work even without adverse feedback` fail (two sets
instead of one). Restoring this implementation makes it pass.

The native test cases in `TrainingSessionDraftTests` cover explicit review,
failed apply/retry, account changes, receipts and variant/reason encoding. The
training UI fixture includes apply and reject journeys in `LogYourBodyUITests`.
These require the real Xcode runner, coverage nonregression and installed-build
receipts before native release. Linux SwiftLint cannot substitute for that evidence.

The disposable PostgreSQL verifier includes the additive migration and checks
training fingerprint freshness, competing heads, unfinished-session authority,
idempotent decisions and preserved next-block history:

```sh
python3 apps/web/db/tests/verify-training-revisions.py --postgres-bin /path/to/postgresql/bin
```

Local qualification on the final source diff:

- `pnpm lint` and `pnpm typecheck`: passed.
- Focused engine/service/revision/route Jest run: 115 tests passed.
- `pnpm --filter logyourbody test:ci`: 124 Jest suites / 1,160 tests and three voice adapter tests passed.
- `VITEST_MAX_WORKERS=1 pnpm --filter @logyourbody/shared-lib test`: 156 Vitest tests and 122 Node tests passed.
- Root `pnpm test` was attempted, including `--concurrency=1`; two shared tests hit their existing five-second limits with default parallel workers. The complete shared suite passed with one worker and unchanged limits/assertions.
- `pnpm check:neon-migrations`: passed.
- Disposable PostgreSQL 16.15 verifier: all 20 cases passed. Ubuntu PostgreSQL packages were extracted into `/tmp`; nothing was installed system-wide and no external database was contacted.
- Strict SwiftLint with `--no-cache`: no violations in the five changed Swift files. Five SourceKit-dependent rules were unavailable on this Linux host.

This host has no Xcode, simulator or Swift compiler. Native execution/coverage and
installed-build evidence remain unverified. Required repository checks and
governed admission remain intact; no approval labels, migration deployment,
feature rollout, push or PR operation are part of this local handoff.

GitHub readback confirmed PR #1210 (`feat/chatgpt-mcp-training`) and the related
LYB-109 load-prefill PR #1212 are merged. Their MCP, OAuth, voice and load-input
implementations remain in place; no competing MCP surface was added. The existing
shared training engine/service is extended in this branch.
