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

## Compatibility with delegated programming

Cycle intents remain version 1 proposals on the shared route, including when the
separate delegated-programming gate is enabled. Version 2 proposals retain their
existing trainer authority, evidence freshness, delayed-workout decisions and
receipt behavior. A cycle revision cannot replace an accepted delegated plan.
The additive cycle migration extends the delegated transaction from main, retaining
both admission paths and their shared owner lock. The cycle schema lives in
`cycle-contract.ts` so the engine does not import the revision/delegation/canvas
module chain during initialization.

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

PR #1541 merge-repair qualification (Node 22.23.2, pnpm 10.34.1):

- `corepack pnpm lint` and `corepack pnpm typecheck`: passed.
- `corepack pnpm --filter logyourbody exec jest --runInBand src/lib/training src/app/api/auth/mobile/training/v1`: 17 suites / 212 tests passed.
- `corepack pnpm --filter logyourbody test:ci`: 126 Jest suites / 1,185 tests and three voice adapter tests passed.
- `PATH=/tmp/pnpm10-shim:$PATH VITEST_MAX_WORKERS=1 corepack pnpm test --concurrency=1`: all eight Turbo tasks passed, including the web production build; shared-lib ran 156 Vitest tests and 122 Node tests. The temporary shim selects the source-pinned Corepack pnpm for child processes.
- `corepack pnpm check:neon-migrations`, `python3 scripts/repository_docs.py`, and the existing correction coverage and ratchet commands against `origin/main`: passed. The ratchet retained its 11 existing public-copy warnings without baseline changes.
- Disposable PostgreSQL 16.15 verifier: all 28 combined cycle/delegation cases passed. With `--cycle-migration` pointing at the original PR migration, the same verifier fails delegated enrollment as expected.
- Restoring the pre-repair route dispatch makes both gate-setting cycle regressions fail with HTTP 400; the repaired dispatch passes both.
- Strict SwiftLint with `--no-cache`: no violations in the five changed Swift files. Five SourceKit-dependent rules were unavailable on Linux.

The sandbox initially blocked test subprocesses and local Unix sockets. The root,
web CI and PostgreSQL checks passed on rerun with normal process/socket access;
no assertions, timeouts or gates were relaxed. This host has no Xcode or simulator.
Native execution/coverage and installed-build evidence remain unverified. Required
repository checks and governed admission remain intact; migration deployment,
feature rollout, push and PR edits are outside this local harness handoff.

GitHub readback confirmed PR #1210 (`feat/chatgpt-mcp-training`) and the related
LYB-109 load-prefill PR #1212 are merged. Their MCP, OAuth, voice and load-input
implementations remain in place; no competing MCP surface was added. The existing
shared training engine/service is extended in this branch.
