# Repeated corrections require mechanization (LYB-209)

Follow the [ledger capture guide](correction-ledger.md) to record each engineering or agent correction in
`packages/shared-lib/corrections.json` as part of the PR that addresses it. Reuse
the fingerprint for the same underlying mistake, even when the wording changes.
Retain receipts so recurrence survives worktrees, workflow reruns, and time gaps.

Each receipt has four required evidence fields, plus the reviewed
[classification and guard or prose-only annotations](correction-coverage.md)
required by CI:

```json
{
  "fingerprint": "preserve-required-checks",
  "correction": "Keep the required check enabled when fixing its failure.",
  "source": "https://github.com/JovieInc/LogYourBody/pull/123#discussion_r456",
  "mechanization": "Add a policy regression test that rejects removal of the check.",
  "guard": {
    "path": "packages/shared-lib/src/example.test.ts",
    "anchor": "rejects removal of the required check"
  },
  "classification": {
    "codebase": {
      "feasible": false,
      "rationale": "This correction governs repository checks, outside an application runtime path."
    },
    "static": {
      "feasible": true,
      "rationale": "A policy test can reject removal of the required check."
    }
  }
}
```

The example is illustrative; record actual sourced corrections rather than
inventing past receipts. Use sanitized evidence links and concise descriptions; never store
secrets, private transcripts, or customer data. A source must be an HTTPS URL
identifying a distinct correction (for example, a review comment permalink).
Replaying the same URL counts once per fingerprint. Separate corrections within
one PR need separate permalinks. Fingerprints are case insensitive, trim outer
whitespace, and replace whitespace with hyphens; use a short, stable key.

The existing Remediation signal workflow invokes the recurrence intake after
verified CI or Deploy pushes to `main`, and during its existing nightly and manual
probe runs on `main`. This includes successful CI runs: filing does not depend on
a red check or on the homepage's two-red guard. No additional clock, workflow,
account, or credential is needed.

The first receipt requires a same-PR guard when feasible under
[LYB-208](correction-mechanization.md); it does not create a recurrence issue.
Two different source URLs with the same fingerprint
automatically upsert one Linear issue on team **LYB**, in **Todo**, labeled
**agent-ready** and with an exact `remediation:correction-<hash>` deduplication
label. Its description includes the correction receipts, proposed guards, repo,
and acceptance criteria requiring deterministic prevention and a failing-then-
passing regression test, warn-then-ratchet handling for existing debt, and the
existing automatic merge queue path after CI passes. Further receipts update
that issue. Completed or canceled
issues retain their state when old evidence is replayed; the intake never treats
a green build as proof the mechanization task is complete.

A stable caller-supplied issue UUID prevents duplicate creates across overlapping
CI, Deploy, and scheduled intakes. Linear's `IssueCreateInput` GraphQL schema
supports caller-supplied issue IDs.
The shared adapter retries a lost create acknowledgment or a create collision by
looking up the same deduplication label again.

The existing `LINEAR_API_KEY` is used. `REMEDIATION_INTAKE_DISABLED=1` remains the
explicit emergency stop. An invalid ledger, missing key/team/state, or API failure
produces a visible warning and step summary; it does not claim filing succeeded
or fail the unrelated production monitor. Receipts remain in Git, so the next
eligible run retries automatically. `CORRECTION_LEDGER_PATH` overrides the ledger
location for replay/testing; normal Actions runs use the tracked ledger.

Verification: `node --test packages/shared-lib/scripts/correction-recurrence.behavior.mjs`.
The same suite runs through `pnpm test` in `@logyourbody/shared-lib`, including the
actual intake CLI, threshold, duplicate receipts, distinct fingerprints, concurrent
creates, lost replies, event admission, emergency stop, and dependency failures.
