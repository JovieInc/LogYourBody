# Five-to-four training offer (LYB-259)

Recorded: 2026-11-01. Parent: LYB-174. Status: accepted default.
Approval basis: LYB-259 explicitly authorizes its recommended default to ship
if unanswered. This records that authorization; no separate human copy review
is claimed.

## Approved threshold and copy

Offer a four-session plan after **three consecutive complete weeks at four of
five requested sessions**, with five still the user's selected weekly capacity.
Use the rolling selector's three most recent complete seven-day attendance
windows. Require four recorded visits in each window, rather than an average of
four across the period. One or two weeks, an incomplete third week, or a broken
pattern does not qualify. A longer uninterrupted pattern remains eligible for
its first offer; it does not generate repeated offers.

> You've trained 4 days a week for 3 weeks. Want a plan built around 4? You can switch back anytime.

Buttons, in order: **Keep 5** / **Use 4**.

Use authenticated recorded attendance, not scheduled opportunities or inferred
misses. Retain LYB-174's visit accounting: completed or partial visits with
logged work count, continuations count once, and separate AM/PM visits remain
distinct. Because the approved copy says **days**, each qualifying week must
also contain four distinct training dates in the recorded local timezone.
Four visits on fewer dates must not be described as four training days.
Known unlogged work or unavailable evidence withholds this offer until the
attendance can be established. A change in selected capacity breaks the pattern;
do not count weeks from an earlier capacity or program as five-session shortfall.

Show one clear offer for the sustained pattern. **Keep 5**, dismissal or no
response preserves the current plan. Remember an answered or dismissed offer
so the continuing pattern does not nag on later opens, retries or syncs.
**Use 4** explicitly requests a four-session plan through the canonical
engine-owned review/admission path. Only a committed change establishes the new
plan; a failed or pending request does not. Keep returning to five available
through that same path, without rewriting completed training or adding catch-up
work. Do not present the offer until that reversal is supported.

Three weeks is the authorized product heuristic within LYB-174's two-to-four-week
range, not a scientific adherence or recovery threshold. The copy observes what
the user did, offers a choice and makes reversal explicit. Do not add failure,
guilt, discipline or lost-progress language. The
[brand ethos](brand-ethos.md) and
[evidence standard](evidence-and-recommendation-standard.md) still apply.

## Created prompt slice: offer four sessions after sustained shortfall

Key: `five_to_four_training_offer`. Status: ready for implementation as one
reviewable PR. This is a repository-local work specification, not a new Linear
issue ID. Dependencies: this decision and the
[LYB-174 rolling selector and canonical admission integration](../engineering/rolling-training-schedule.md).

Extend the existing `attendanceChoice` flow in
`apps/web/src/lib/training/rolling-schedule-signals.ts` and its native review
surface; keep one selector and one plan writer. Today the selector can offer
consolidation after two matching weeks and returns a reversible, unapplied
proposal. It does not implement this three-week decision, approved copy,
remembered response or committed switch/back flow. This decision changes no
runtime behavior and does not certify those gaps as closed.

Implementation acceptance:

- Enforce the approved three-week five-to-four threshold against owned, current
  attendance and selected-capacity history. Preserve visit identity, timestamp
  and timezone provenance; require the distinct dates needed by the copy. Do
  not change other capacity-review policies, including six requested/one
  recorded, or treat missing data as a missed visit.
- Render the exact message and **Keep 5** / **Use 4** actions once the threshold
  qualifies. Keep the offer readable with Dynamic Type and VoiceOver. Preserve
  the plan on dismissal, no response or **Keep 5**; persist handled state so the
  same sustained pattern does not produce repeat prompts.
- Route **Use 4** and a later return to five through the existing deterministic
  engine and canonical revision/admission boundary with explicit user choice,
  current-source checks and idempotent retries. Reuse existing plan persistence
  and offline reconciliation. Distinguish pending, failed and committed states;
  retain completed history and never change a plan merely by showing an offer.
- Use default-off coach/optimizer gates and platform ports; add a default-off
  presentation gate for the new prompt. A disabled gate suppresses the offer.
  Preserve existing safety exclusions and engine ownership of prescriptions.
- Add behavior regressions for one/two weeks; an incomplete third week; exactly
  three and longer qualifying runs; mixed counts with an average of four;
  changed capacity; unknown/unlogged attendance; partial visits, continuations
  and AM/PM visits; distinct local dates and DST boundaries; exact copy/actions;
  dismissal/decline across relaunch and sync; duplicate taps; failed/offline and
  stale requests; committed four-session selection and explicit return to five;
  gate-off behavior; and preservation of logged work. Run the existing server
  suite and real native runner on the changed commit, retaining relevant native
  execution and coverage evidence.

This decision's test plan is documentation review and link/format checks.
Runtime implementation and its tests belong to the created prompt slice. All
other LYB-174 scope and real-device TestFlight evidence remain with the parent.
