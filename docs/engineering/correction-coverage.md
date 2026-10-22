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
it has. This ledger is also the LYB lesson inventory; do not copy Jovie's lesson
ledger into it. LYB-206 requires every receipt to have a retained guard or an
explicit prose-only reason:

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
or `human`, as defined by LYB-203. A codebase/static rule must have a guard and is mechanized only
when its local guard file contains the specified anchor (at least 16 characters).
Proposed guards, absent files and missing anchors fail CI. Prose and human review
must instead supply a nonblank `proseOnlyReason` explaining why deterministic
enforcement is unsuitable, for example `"Requires account-owner legal attestation."`.
They earn no mechanization credit. A guarded receipt cannot also be prose-only.
Unclassified receipts fail CI. All receipts for one fingerprint must carry identical
coverage annotations, including their prose-only reason. Historical baseline
reports still retain unclassified or unguarded rules in the denominator.

Every row reports `mechanized / total distinct rules` and its percentage; the
overall row includes every level. Zero rules is **N/A**, never 100%. The committed
ledger currently contains no receipts, so initial coverage is N/A. These are
reviewed source-linkage metrics, not proof that the guards executed or that every
historical correction has been captured.

Run from the repository root:

```sh
node packages/shared-lib/scripts/correction-coverage.mjs
node packages/shared-lib/scripts/correction-coverage.mjs --base-ref origin/main
node packages/shared-lib/scripts/jovie-separation.mjs
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

The same required change-detection job runs the Jovie separation grep on every
diff, including docs-only PRs. It scans tracked and new nonignored code under
`apps/`, `agent/`, `packages/`, `scripts/` and `.github/`, skipping symlinks and
non-code assets. It rejects Jovie-specific environment/constant identifiers
(`JOVIE_*`), the Jovie Linear team UUID, Jovie OAuth client IDs (`jovie-web` /
`jovie-ios`), and Jovie feedback/correction schema namespaces. Matching is case
insensitive and failures name the file and line without dumping source contents.
Shared Jovie auth, JovieKit, design tokens, packages and provenance references
remain supported. The six existing auth, GitHub App and Mac runner environment
keys are explicitly allowed. The existing vendored Linear adapter, its compatibility
tests and the required GBrain Doppler configuration have reasoned, per-identifier
occurrence limits; extra occurrences or copies into another file fail.
Exceptions live in `jovie-separation.mjs` and
require review alongside any integration change. The behavioral suite runs both
directly in CI and through the normal shared-lib test task.

Publication uses the existing `LINEAR_API_KEY` and honors
`REMEDIATION_INTAKE_DISABLED=1`. Missing credentials, the wrong owner team, invalid
data or provider failures produce an explicit **did NOT post** warning and job
summary; they do not claim successful delivery or alter remediation's existing
failure policy. The report changes no issue state, labels or owner discussion.
After merge, verify the report comment on LYB-203 and its source commit link.
