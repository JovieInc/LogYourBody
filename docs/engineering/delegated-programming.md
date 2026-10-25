# Delegated programming (LYB-130)

LYB recommends one plan; the user reviews and steers it. The existing training
revision service owns both enrollment and later changes. Accepted state remains
in the existing `program_setup` record, with an immutable revision and proposal
receipt in the existing training ledger. The LYB-119 canvas supplies the plan
schema and reviewed draft/priority policies; it is not copied into another plan
builder. Once a delegated program is accepted, both the API and owner-locked canvas storage refuse a second canvas ledger write. The accepted canvas plan feeds the existing LYB-129 session engine and
LYB-128 controller.

## Admission and rollout

Apply `20261025010000_delegated_training_revisions.sql` before deploying the
adapter. The migration extends the owner-locked command and adds an owner-scoped
training-evidence fingerprint; it does not change training consent or public
record-sync admission. Both `LYB_HYPERTROPHY_COACH_API_ENABLED=true` and
`LYB_DELEGATED_PROGRAMMING_ENABLED=true` are required for new proposals. Native
also requires the default-off Platform flag `delegated_programming_v1`.
Existing baseline programs are adopted by a reviewed recommendation using the same setup ID; their completed history is retained. No production migration, provider change or rollout is performed by this work.

The existing `/api/auth/mobile/training/v1/program-proposals` endpoint accepts:

- GET: current generation, known canonical `training_inputs`, current setup,
  current pending proposal, movement choices and applied history. `?id=<uuid>`
  reads a proposal; `?history=true` returns the owned immutable ledger.
- POST: `{requestId, expectedGeneration, reason, intent}` or an `utterance` in
  place of `intent`. Optional `baseProposalId` steers an unaccepted draft without
  changing it in place. Supported intents are `recommend`, `keep`, `exclude`,
  `prioritize`, `schedule`, `next_block`, `restore`, `authorize_trainer` and
  `delegate_coach`. Unknown quantities or authority fields fail closed.
- PATCH: `{requestId, proposalId, decision: "apply" | "reject"}`. Only a committed
  receipt can claim application. Reusing an identity with different content
  conflicts. Native additionally reads the accepted revision back before start.

A recommendation requires an outcome, experience, realistic days/time budget,
known equipment, explicit movement exclusions and known limitations. Optional
positive preferences and goal date are not required. Missing consequential
inputs produce one focused question, with no proposal or guessed prescription.
Known values come from canonical profile `training_inputs` or the accepted plan.
Unknown restrictions and incompatible kept variants require review. Nutrition
and activity engines remain disabled; no prescriptions are introduced for them.

Bearer identity determines the actor; a request cannot supply actor/authority.
A trainer uses `?owner=<subject>` and needs that owner's current accepted trainer
grant. Only the owner can change grants or delegate. Coach recommendations are
reviewable; internal coach application requires an explicit accepted delegation.
Revoking delegation remains a user revision. Native, chat/voice and the MCP
`revise_training_program` tool all call this revision service. Chat only proposes
and points to review; it cannot apply from generated conversational text.

## Policy and lifecycle

The planner redistributes existing reviewed canvas work across two to six days.
Its duration is a disclosed approximation using workout mode's existing three
minutes per set budget. It can reduce existing sets to fit but never fabricates
loads, new dose rules or precise physiological personalization from experience.
All numerical prescriptions remain deterministic. Final-week deload work uses
the engine's existing reduced set and effort values; block lengths are four,
five or six weeks. The engine retains its recovery and safety stops.

Equipment, exact variant preferences, exclusions and reviewed limitations are
durable. A priority is explicitly scoped to this block; repeated steering does
not accumulate dose. Next-block preparation expires it unless the user explicitly
renews it on the new draft. Kept variants retain their exact catalog IDs and use
only their own completed set history for progression. A single-set deload retains its own known load as a hold; it cannot authorize a load increase. Both automatic alternatives
and explicit swaps continue to enforce durable eligibility.

Calendar time alone cannot advance a delegated block. Each planned week/slot
needs recorded completed training with actual logged work; missed and empty-ended
workouts do not count. Empty-ended attempts get new session identities when the
work remains due. Schedule revisions retain the completion requirements of weeks
already completed under the prior revision, while open weeks use the new schedule.
Completed history is never rewritten to fit the new plan.

`GET /next` detects block completion and persists an idempotent next-block draft.
It presents staying/changing/why/expiring information and Start next block / Review
changes. Steering a prepared draft creates another immutable proposal. The user
can accept directly from Today without opening a manual builder. A rejected draft
can be deliberately renewed through `next_block`; rejection never silently applies.

Each proposal includes actor/authority, reason/intent, exact prior setup and typed
diff, full proposed state, evidence IDs, snapshot freshness and separate fresh/stale/missing training and feedback signals, policy checks,
review point and rollback revision. Owner incarnation, generation, canonical
profile/setup fingerprints, head and all training evidence are checked again
inside the transaction. Active workouts delay application; the owner ledger retains an idempotent delayed-attempt audit with actor, reason, timestamp and review point. Competing revisions
admit one winner. Setup, revision, head and receipt commit together or roll back.
Restoration creates a new revision, revalidates current safety constraints, and
never rewinds completed history or trainer authority.

## Structured steering writer (LYB-278)

`persistSteeringRevision` accepts an already reviewed structured record containing
`revisionId`, `priorityFocus` (muscles and optional upper-chest emphasis via the
explicit `upperChest` boolean), opaque nullable `constraintId`, `actor`, and
`rationale`. The authenticated actor must match the record and current program
authority. The caller supplies the existing rollout gate and a resolved
health-policy decision; unresolved decisions fail closed. This internal writer
adds no HTTP, MCP, chat, or native entry point.

The saved focus uses the existing block-scoped `temporaryPriority`; the constraint
ID is additive program metadata. The existing `TrainingRevisionsPort` stores a
version 2 proposal and atomically applies the saved setup and immutable revision.
The record's revision ID identifies the proposal, decision and revision; changed
content under that identity conflicts, and an identical retry reuses its receipt.
The immutable proposal retains actor and rationale as `actor` and `reason`.
Storage refusal or failure cannot claim success, and pending retries retain the
existing context, active-workout and consent checks.

Only a `movement_constraint` health decision requests a restriction through the
request-only LYB-113 `SteeringSubstitutionsPort`, using LYB-113's existing
`maxTrunkDemand` / `excludedConcerns` types. That boundary must deduplicate requests
by revision ID, including retries after interrupted persistence. An unavailable
or refused request prevents the steering write. The writer defines no health
policy or clinical wording. It saves intent without computing loads/volume or
changing the prescription; implementing a movement change remains with LYB-113.

`steering-revision.test.ts` uses an in-memory saved program and fake LYB-37
boundary, with planner and prescription functions configured to throw if called.
It covers audit persistence, duplicate/conflicting IDs, conditional restriction
requests, unchanged prescriptions and storage/authority/policy failures.

## Verification

`delegated-revisions.test.ts` exercises all eight issue fixtures through proposal,
apply, completed set logging, next-block preparation and the existing workout and
controller services. Additional cases cover initial-draft steering, renewal,
concurrent changes, trainer/delegation authority, restore, stale evidence and
active-workout delay. HTTP/MCP and chat/voice contract tests verify their shared
service boundary and default-off admission. Native tests cover known inputs,
focused questions, retry identity, account ownership and matching committed
readback before start.

The real PostgreSQL suite also covers delegated enrollment/retry, concurrent
edits, changed feedback, trainer authorization and injected setup-update rollback:

```sh
python3 apps/web/db/tests/verify-training-revisions.py --postgres-bin /path/to/postgresql/16/bin
```

Run `pnpm lint`, `pnpm typecheck`, `pnpm test` and native runner gates before rollout.
Linux SwiftLint cannot run SourceKit rules or supply native execution, coverage,
UI or installed-build evidence. Those remain required on the real native runner.
