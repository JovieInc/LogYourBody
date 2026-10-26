# Adaptive recovery trials (LYB-112)

This first increment extends the canonical programming engine and training record
port. It is not full native acceptance. Enable only for internal certification
with both `LYB_HYPERTROPHY_COACH_API_ENABLED=true` and
`LYB_ADAPTIVE_RECOVERY_ENABLED=true`; both remain off by default.

The bearer API at `/api/auth/mobile/training/v1/recovery-trials` supports:

- `GET ?muscle=shoulders&exerciseId=dumbbell_lateral_raise&goal=emphasize`:
  evaluate stored work and observations without writes; return existing trials.
- `POST {requestId, muscle, exerciseId, goal}`: persist a versioned trial proposal.
- `PATCH {trialId, expectedRevision, decision}`: `apply`, `reject`, `revert`, or
  `review`. Only `apply` enables a proposed prescription change. Review records an
  outcome and never silently changes approval or the plan.

Trials are `recovery_trial` rows in `training_feedback`, separate from observation
rows. They retain the original prescription, actual completed sets (including
correction metadata), observation IDs, inference, intervention, hypothesis,
policy version, approval state, review conditions and append-only outcome history.
They inherit the existing owner, export, consent-revocation and deletion lifecycle.
No new collection, MCP implementation or progression engine is introduced.

The database command holds the existing account-owner lock and compares the exact
training-record snapshot plus trial revision before writing. A concurrent log,
correction, plan write, decision, consent revocation or owner replacement cannot
apply a stale proposal. Migration absence fails closed; generic record push is
never a fallback. The current snapshot covers all retained training rows; this
is conservative and may require recreating a proposal after unrelated work.

## Policy and bounds

`adaptive-recovery-v1` compares the corresponding first work set across completed
exposures, with equal exercise variant, setup, load, RIR, rest, order, range of
motion and set format. Ordinary later-set rep loss is not a declining exposure.
Local, supporting-muscle and whole-body feedback remain distinct. Missing,
conflicting, stale, historical or changed-context data cannot authorize escalation.
One adverse result can justify an immediate reversible proposal without proving
its cause or a personal recovery-hour constant.

An executable reduction reuses the shipped engine's one-set recovery dose.
The repeated-decline/high-soreness review values and freshness window come from
the existing controller policy. A local limitation plus comparable deterioration
can propose reducing the existing dose immediately. Pain requires movement review;
whole-body limitation requires recovery review. Persisting adversity at the
reduced dose also returns recovery review, rather than assuming the dose is safe.

Favorable comparable response holds. Approved side-delt emphasis can produce a
parameter-review proposal, with existing evidence IDs, for the missing set
increment, personal cap including overlap, trial duration and allocation/time
bounds. No numerical increase is executable in this version. Grow and Maintain
do not inherit mandatory weekly increases. No unknown load increment is guessed.

The source rationale for conditional recovery is supported by
[Morán-Navarro et al. (2017)](https://pubmed.ncbi.nlm.nih.gov/28965198/), a study of
ten trained men using bench press and squat protocols. Its findings do not
establish an individual's recovery hours, a side-delt set cap or a universal
progression formula. Existing opaque evidence IDs retain their existing meanings;
this paper is not assigned an invented knowledge ID.

## Prescription application and integration boundaries

Applying a reduction changes only that exercise's set count in future sessions
through `getOrCreateNextWorkout`; fractional volume is recalculated using existing
compound contributions. Other muscles, visits, variants, loads and reps remain
under their existing owners. The workout response sets `decision.nextAction` to the
session explanation. The next-session card and live workout header show that
explanation only when it starts with `Applied recovery trial:`. A session already
started retains its prescription and that next action. Rejection does not alter
work. Reversion restores the engine's prior future plan subject to current
safety/recovery constraints. Trials expire at the next block; deload cannot
activate a pending trial or carry forward an escalation.

The next comparable completed exposure can be reviewed as retain, revert or
inconclusive; outcome history remains separate from the intervention and its
approval. Reversion always requires a decision. Repeated adversity at a reduced
dose warrants recovery review, not automatic restoration of more work.

Still required before the issue is complete:

- A native recovery-trial review screen. Apply, reject and revert currently use the
  authenticated recovery-trials API. The existing workout surfaces only display the
  applied next action.
- LYB-174 timestamped AM/PM slots and executable spacing changes. This increment
  returns `respace` with rationale but cannot invent slots in the current weekly
  2/3-session baseline. It does not rewrite Tim's five-visit intent.
- LYB-176 reviewed substitution application for a supporting-muscle limitation.
- Reviewed numerical escalation policy and individualized allocation bounds.
- Native exact-head Xcode/coverage checks and installed-build replay of Monday
  dose → Tuesday decline → reviewed adjustment → comparable exposure → outcome.

Regression coverage is in `recovery.test.ts`, the authenticated recovery route
tests, adapter tests, and the existing disposable PostgreSQL16 training-mutation
verifier. These checks do not constitute native installed-build evidence.
