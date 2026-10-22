# LYB correction coverage (LYB-207)

The correction-pyramid owner loop posts coverage to the existing parent epic,
**LYB-203**, using the existing main-only
Remediation signal intake. CI completions on main and the existing nightly/manual
probe runs publish a report. Deploy events add no extra report. Each checked-out
main revision is posted once on replay, with an immutable commit link; comments
are paginated before deduplication. Other owner reports can consume the same
table from the GitHub job summary or the CLI's JSON output. No additional clock,
service, account or credential is introduced.

The metric reads `packages/shared-lib/corrections.json`, retaining the receipt
contract and recurrence behavior from [LYB-209](correction-recurrence.md). Count
one rule per normalized fingerprint, regardless of how many correction receipts
it has. Each current receipt must include a reviewed classification (LYB-205):

```json
{
  "fingerprint": "preserve-required-checks",
  "correction": "Keep the required check enabled when fixing its failure.",
  "source": "https://github.com/JovieInc/LogYourBody/pull/123#discussion_r456",
  "mechanization": "Add a policy regression test rejecting removal of the check.",
  "classification": {
    "codebase": {
      "feasible": false,
      "rationale": "The correction governs repository checks rather than an application runtime path."
    },
    "static": {
      "feasible": true,
      "rationale": "A policy regression test can deterministically reject removal of the required check."
    }
  },
  "level": "static",
  "guard": {
    "path": "packages/shared-lib/src/example.test.ts",
    "anchor": "rejects removal of the required check"
  }
}
```

This is an illustrative receipt, not an assertion that the example guard exists.
The classifier evaluates feasibility in LYB-203 priority order and selects the
first feasible level. Assessments must describe the correction's full invariant,
not just a convenient partial check:

| Level      | When it is enforceable here                                                                                                                                                 |
| ---------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `codebase` | Runtime logic, types, schema constraints, or API design can prevent the mistake by construction. Prefer this even when a lint or review could also catch it.                |
| `static`   | A deterministic lint, typecheck, test, or CI check can detect the violation when prevention by construction is not feasible.                                                |
| `prose`    | A precise repository instruction or runbook can guide the action, but no reliable code or static guard can express the full rule.                                           |
| `human`    | Contextual judgment, an external decision, or account-owner authority is unavoidable, and prose alone cannot enforce the correction. Name that dependency in the rationale. |

Provide a boolean `feasible` and a nonblank `rationale` for every level up to and
including the selected level. For each rejected level, explain why it cannot
enforce this correction; for the selected level, describe the concrete mechanism.
Later levels may be omitted and do not affect selection. There is no implicit
human fallback. Empty assessments, missing reasons, unknown levels, and a
redundant `level` that disagrees with the result fail validation. The `level`
field is optional when classification is present.

These are reviewed feasibility decisions, not keyword guesses or proof that a
guard has shipped. Reviewers must check the rationale against the correction's
source and code surface. Lack of an implemented guard does not justify choosing
a higher level. JSON output includes the selected level, rationale, and ordered
assessments; the existing owner report includes the same routing explanation.

The current ledger is validated by the existing coverage CLI and CI invocation;
every receipt, including duplicate receipts, must be classified. Immutable base
revisions remain readable: old level-only or unannotated receipts retain their
historical level or `unclassified` denominator when comparing coverage.

A codebase/static rule is mechanized only
when its local guard file contains the specified anchor (at least 16 characters).
Proposed guards, absent files, missing anchors, prose and human review earn no
mechanization credit. All receipts for one fingerprint must carry identical
classification and guard annotations; selecting a route earns no mechanization
credit by itself.

Every row reports `mechanized / total distinct rules` and its percentage; the
overall row includes every level. Zero rules is **N/A**, never 100%. The committed
ledger currently contains no receipts, so initial coverage is N/A. These are
reviewed source-linkage metrics, not proof that the guards executed or that every
historical correction has been captured.

Run from the repository root:

```sh
node packages/shared-lib/scripts/correction-coverage.mjs
node packages/shared-lib/scripts/correction-coverage.mjs --base-ref origin/main
pnpm test --filter=@logyourbody/shared-lib
```

The existing required CI path checks coverage on **every diff**, including
changes outside the ledger. It fetches the event's exact base revision (PR base,
merge-group base, or the previous main commit), then reads both its ledger and
its guard files from that Git revision. Missing or unreadable baseline evidence
fails the check. No editable percentage-baseline file is used.

CI rejects any decrease in the unrounded overall or nonempty per-level ratio,
removal of a retained rule, loss of a mechanized guard, or movement of an already
mechanized rule from codebase to static/prose/human. Moving all rules out of a
level by promoting them is allowed; an empty level has no percentage to compare.
New unmechanized rules can lower coverage and must be addressed in the same PR.
Empty baselines establish no percentage floor. Existing quality gates remain in
place.

Publication uses the existing `LINEAR_API_KEY` and honors
`REMEDIATION_INTAKE_DISABLED=1`. Missing credentials, the wrong owner team, invalid
data or provider failures produce an explicit **did NOT post** warning and job
summary; they do not claim successful delivery or alter remediation's existing
failure policy. The report changes no issue state, labels or owner discussion.
After merge, verify the report comment on LYB-203 and its source commit link.
