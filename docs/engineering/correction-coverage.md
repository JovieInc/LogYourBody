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
it has. Coverage annotations are optional on existing receipts:

```json
{
  "fingerprint": "preserve-required-checks",
  "correction": "Keep the required check enabled when fixing its failure.",
  "source": "https://github.com/JovieInc/LogYourBody/pull/123#discussion_r456",
  "mechanization": "Add a policy regression test rejecting removal of the check.",
  "level": "static",
  "guard": {
    "path": "packages/shared-lib/src/example.test.ts",
    "anchor": "rejects removal of the required check"
  }
}
```

This is an illustrative receipt, not an assertion that the example guard exists.
Use the current rule's intended enforcement level: `codebase`, `static`, `prose`,
or `human`, as defined by LYB-203. Unannotated receipts stay `unclassified` and
remain in the overall denominator. A codebase/static rule is mechanized only
when its local guard file contains the specified anchor (at least 16 characters).
Proposed guards, absent files, missing anchors, prose and human review earn no
mechanization credit. All receipts for one fingerprint must carry identical
coverage annotations; classification and guard selection remain separate work.

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
