# Exercise-swap pain guidance (LYB-257)

Recorded: 2026-11-01. Parent: LYB-176. Status: accepted default.
Approval basis: LYB-257 explicitly authorizes its recommended default to ship
if unanswered. This records that authorization; no separate clinician or human
copy review is claimed.

## Approved wording

LYB-298 supersedes the original LYB-257 wording with its explicitly authorized
default below. The shared runtime source is
[`CONCERNING_PAIN_MESSAGE`](../../apps/web/src/lib/training/pain-policy.ts).

> Stop this movement. If pain is persistent, worsening, or includes numbness, weakness, or other neurologic symptoms, seek evaluation from a qualified clinician.

Show the entire message on **any pain report** during a movement. Do not wait
for a severity score, a repeated report, another set or a duration threshold.
Use the same message for reported numbness, weakness or other concerning
symptoms, including when pain is absent or unreported. It makes no diagnosis,
injury prediction, treatment recommendation or assurance that a swap is safe.

## Trigger and clearance thresholds

| Report or state                                                                                                                    | Required behavior                                                                                                                                                                                                                                                |
| ---------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Any reported pain, including any nonzero value on the existing joint-discomfort scale or an explicit pain symptom flag             | Show the approved message, stop the affected movement and withhold both different-exercise and same-exercise setup suggestions. Do not require the separate deload engine's higher pain threshold.                                                               |
| Pain persists or gets worse                                                                                                        | Encourage clinician evaluation through the same message. Keep swaps withheld while pain remains; do not invent a number of hours, days, reports or a tolerable pain score. Persistence and worsening are user reports, not diagnoses inferred from elapsed time. |
| Numbness, weakness or other concerning/neurologic symptoms, with or without pain                                                   | Show the message and retain the existing symptom-safety hold. The clinician guidance does not depend on pain also persisting or worsening.                                                                                                                       |
| User explicitly marks the reported movement pain as gone                                                                           | Permit a fresh eligibility review only after that report is saved. This is a necessary condition for suggesting swaps after pain, not medical clearance or automatic approval, resumption or removal of another safety hold.                                     |
| Missing/unreported pain, a lower but nonzero score, a dismissed message, an expired rest timer, a reopened screen or a new session | None establishes that previously reported pain is gone. Preserve the unresolved report and withhold swaps.                                                                                                                                                       |
| Non-pain back/trunk fatigue or general exhaustion alone                                                                            | Preserve the existing distinct observation and substitution rules; do not infer pain or a diagnosis from fatigue.                                                                                                                                                |

Record resolution as a subsequent user report tied to the affected movement and
pain observation; retain the original report. A false original report may still
be corrected through the existing append-only correction path. Neither a pain
resolution nor a correction may silently clear independent symptoms or an
engine-owned session pause. If pain recurs, stop and withhold suggestions again.
An equipment change, added support or belt cannot clear symptoms.

The [brand ethos](brand-ethos.md) and
[evidence standard](evidence-and-recommendation-standard.md) govern this copy.
The thresholds above are the authorized conservative product policy, not a
validated clinical triage or return-to-exercise protocol.

## Created UI/logic slice: exercise-swap pain guidance

Key: `exercise_swap_pain_guidance`. Status: ready for implementation as one
reviewable PR. This is a repository-local work specification, not a new Linear
issue ID. Dependencies: this decision and the
[LYB-176 substitution engine/integration](../engineering/training-alternatives.md).

Extend the existing movement-response flow and deterministic review/action
boundary; keep one implementation. The existing
`TrainingSelectionView.swift` records pain and renders the server's message;
`selection.ts` and `alternatives.ts` enforce symptom exclusions. LYB-298 shares
the approved server copy and concerning-pain policy with selection and swap
approval. The native flow still offers no explicit pain-resolution confirmation;
that gap and the remaining UI/logic acceptance below stay with this follow-up.

Implementation acceptance:

- Render the exact approved message immediately when pain or concerning
  symptoms are reported, including while saving or offline. Keep it readable
  with Dynamic Type and VoiceOver. Pausing and withholding suggestions must
  not depend on a successful review request.
- Add an explicit **Pain is gone** confirmation scoped to the original movement
  report. Save that subsequent observation through the existing feedback
  journal; failed/pending saves, retries and relaunches must not establish
  clearance. Do not reinterpret merely dismissing the warning or resetting a
  picker as this confirmation.
- Enforce withholding in both proposal and swap-approval paths. After a saved
  resolution, request a fresh authoritative review and preserve all other
  symptom, session-pause, equipment and catalog exclusions. A stale candidate
  or forged direct approval must not bypass the hold; selecting a candidate
  still requires the existing explicit swap approval and revision checks.
- Use the existing default-off exercise-selection rollout and platform ports
  (`exercise_selection_v1`, `LYB_EXERCISE_SELECTION_ENABLED` and the coach gates).
  Keep existing safety holds effective when a presentation gate is off. Do not
  change the general deload/recovery policy or generate training prescriptions.
- Add behavior regressions for the lowest nonzero pain score and explicit pain
  flag; numbness/weakness without pain; persistent/worsening pain; missing or
  reduced pain; dismissal and elapsed time; failed/offline resolution and
  relaunch; saved resolution with a remaining independent safety hold; fresh
  eligible review after resolution; stale/forged approvals; recurring pain;
  and non-pain fatigue. Assert exact copy and no suggested alternatives during
  a hold. Run the existing server suite and real native runner on the changed
  commit, retaining relevant native execution and coverage evidence.

This decision's test plan is documentation review and link/format checks.
Runtime implementation and its tests belong to the created slice. All other
LYB-176 scope and real-device TestFlight evidence remain with the parent.
