# Rolling scheduling proposals (LYB-174)

This increment extends the LYB-165 optimizer from merged PR #1383. Its existing
authenticated `/api/auth/mobile/training/v1/optimizations` endpoint accepts an
optional `rollingSchedule` context. Both existing coach API and optimizer flags
must be enabled. Applied recovery decisions additionally require the existing
adaptive-recovery gate. All remain off by default; no rollout changes are included.

Machine: extended `apps/web/src/lib/training/rolling-session.ts` and the existing
optimizer/certifier with `apps/web/src/lib/training/rolling-schedule.ts`.
There is one programming engine; this extension only allocates its retained work.

## Inputs and authority

The context schema defines explicitly offered slots with IDs, offset-bearing
timestamps, IANA timezone, location, concrete equipment, optional genuine time
cap, visit ID and session-group ID. Distinct AM/PM visits have distinct visit IDs;
grouping them never turns them into one attendance event. A continuation names
the partial session and retains its visit and group IDs. A separate resumed
visit has a new visit ID. Canceled opportunities receive no work.

At the HTTP boundary, `ownedRollingScheduleSource` replaces caller claims about
prescriptions, history, logs, observations, applied trials, attendance start,
requested capacity, block and rotation identity with authenticated records and
the existing engine's microcycle. Durable exclusions are merged with offered
constraints. Unavailable evidence fails closed. Propose and accept both rebuild
this source, whose hash includes retained records, including correction and trial
history. A changed owned snapshot invalidates the old proposal. Another owner's
records never enter the source. Slot inventory and timing are supplied estimates;
they do not certify equipment availability or measured exercise duration.

## Allocation

An approved rotation is a finite set of work identities: rotation, template,
exercise and original set number. Actual logged identities are removed once;
missed/empty visits do not move the completion cursor. A partial session advances
the cursor only for choosing other pending work, and its unfinished identities
remain available. Prior rotations still contribute actual timestamped 7/14-day
volume, including catalog compound overlap, without consuming the current
rotation's identities. This proposal never generates the next rotation's dose.

Slots are ordered by instants, rather than weekday names. The shared rolling
cursor orders candidates. Each allocation moves that candidate to the end, so a
time-trimmed remainder cannot monopolize every subsequent visit. A slot's own
eligible priority can lead that slot; global emphasis does not automatically
repeat first in both visits. Edited exercise order is retained. Each slot uses
at most one template's remaining work, bounded by its existing approved dose;
there is no merged catch-up workout. Finite opportunities can leave work
unallocated, with an explicit move/reduce/rest or request-opportunity tradeoff.
The trailing seven-day visit count includes actual and proposed distinct visits;
exceeding agreed capacity requires review, even when more slots were offered.

Fresh explicit local/supporting limitations constrain contributing exercises;
whole-body limitations constrain all candidates. The newest observation for a
scope supersedes older ones; same-time conflicts retain uncertainty and the
limitation. Catalog equipment and pain exclusions remain authoritative. Applied
LYB-112 set reductions reuse `applyRecoveryTrials`; completed work is never cut.
Applied spacing/substitution/recovery-review decisions defer implicated work
instead of returning only a warning. Reject/revert rebuilds the prior future
allocation from original work and actual logs. It does not rewrite history.
The current LYB-112 admission only applies reductions; executable learned spacing
decisions still need that issue's governed policy extension. Variant/pain edits
must be reviewed separately before rebuilding a rolling allocation. Saved
session edits and prescribed effort, including deload RIR, remain authoritative.

AM/PM opportunities sharing a session group are evaluated together. Reserving
later priority work constrains earlier direct/assisting work, including pulling
before curls and grip before forearm work. Actual earlier work with overlapping
demands in that group can remove the later candidate, including across midnight
and DST. Otherwise suitable muscles remain candidates. A new visit is not a
clean fatigue slate. Later proposals must be reevaluated after actual early work.

Elapsed hours, load, reps and RIR are inspectable context, not a numerical recovery
score. No personal 30/32-hour constant, hypothetical set quota or inferred
percentage is installed. The current LYB-112 contract does not supply a reviewed
exact-hour readiness model. Consequently, deferring work does not automatically
make a later slot physiologically ready; allocations remain conditional on
current context, warm-up performance and symptoms. Stale, conflicting and
unlogged observations remain visible.

`planSessionDuration` derives time from retained work plus supplied warm-up,
execution, rest and transition estimates. An omitted cap has no duration ceiling.
Extra time adds no sets. A genuine cap trims lower-value work while protecting
eligible priority touches; omitted identities remain explicit. The original
prescribing engine remains responsible for productive volume, marginal benefit
and set-quality bounds. Allocation is not approval of an excessive input dose.

Attendance produces at most one reversible choice after two to four complete
weeks with a repeated recorded pattern. Five requested/four recorded offers four;
six/one requests capacity review because the shipped programming engine does not
support a one-visit prescription. One disrupted week, no logged visits or known
unlogged work cannot silently change capacity. Continuations count once; separate
AM/PM visits count separately. No program is changed by this choice.

The accepted [LYB-259 decision](../product/training-frequency-consolidation.md)
sets the five-to-four offer to three consecutive complete weeks at four of five
and records its exact copy and **Keep 5** / **Use 4** actions. It also creates
the prompt implementation slice. The current selector still permits a two-week
offer; that threshold, prompt presentation, remembered responses and committed
switch/back behavior remain implementation gaps, not shipped behavior.

## Persistence and remaining acceptance

The existing optimizer acceptance certifies and returns the complete allocation
receipt. It still returns `persisted: false`, `writesPerformed: false` and
`enrollment: false`. This increment does **not** bind that receipt to future
native prescriptions, persist offered slots, change onboarding's legacy duration
contract, add an offline scheduling writer, or implement native review/undo.
The canonical execution service continues to use its current scheduling policy.
Existing set logging, correction, offline and partial-session storage are reused
as read-only evidence, with no alternative writer or database migration.

Full LYB-174 remains incomplete until accepted allocations flow through the
canonical revision/admission transaction into LYB-129 execution, including
reschedule/undo concurrency and native offline replay. Native exact-head tests,
coverage, and installed TestFlight scenarios (busy hard-cap user versus an
unrestricted committed user included) are still required. Local Jest evidence is
not TestFlight or production shipment evidence. The harness owns push, PR and merge.

## Verification

The required web Jest suite includes `rolling-schedule.test.ts` and the existing
optimizer HTTP tests. Cases cover weekend/missed rotation, half-session identities,
continuation versus new visit, applied/rejected/reverted decisions, local versus
whole-body limitation, uncertain feedback, split interference, DST elapsed time,
cancellation/rescheduling, time caps, exclusions, sustained attendance and
certification tampering. API cases exercise owned source reconstruction, source
changes at accept, owner isolation, unavailable evidence and no writes. Existing
duration/recovery suites retain their productivity and learning-policy cases.
