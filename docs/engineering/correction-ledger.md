# LYB correction ledger (LYB-204)

[`packages/shared-lib/corrections.json`](../../packages/shared-lib/corrections.json)
is the single LYB lessons and guards file. Add a receipt in the PR addressing a
correction, starting with its first occurrence. Keep LYB evidence separate from
Jovie's ledger. The inventory covers recorded receipts; it does not claim every
historical chat, review or revert has been imported.

Capture corrections from these sources:

| Origin             | Evidence to retain                                                                                                                                                                                                                    |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tim chat or memory | A stable HTTPS message permalink or a durable GBrain page containing a sanitized correction and its provenance. If the chat has no durable link, first preserve that summary in the relevant LYB issue comment and use its permalink. |
| PR review          | The specific review or inline comment permalink, including its fragment.                                                                                                                                                              |
| Linear comment     | The specific LYB comment permalink; use an issue URL when the correction is in its description.                                                                                                                                       |
| Revert             | The immutable revert commit URL and a concise explanation of the corrected mistake, based on the commit or linked discussion. A revert alone does not establish a new rule.                                                           |

Verify the source before recording it. Preserve only the concise lesson and
sanitized evidence URL; never copy private transcripts, credentials, signed
download links or customer data. Do not invent historical receipts from memory
or treat replaying the same evidence as another correction.

For each receipt:

1. Reuse the short `fingerprint` for the same underlying mistake. Identity trims
   outer whitespace, folds case and replaces whitespace with hyphens.
2. Set `correction` to the lesson, `source` to its HTTPS evidence URL, and
   `mechanization` to the concrete prevention mechanism.
   Register a new evidence URL in the product registry's endpoint allowlist
   with its reason, then run `pnpm product:generate` and `pnpm product:check`;
   the existing URL drift guard applies to ledger receipts too.
3. Review `classification` in priority order: codebase, static, prose, human.
   Provide feasibility and rationale through the first feasible level. The
   selected level is derived. Run the deterministic classifier below to save
   that `level` and its matching `ruleId` on every receipt.
4. Link the existing or new `guard.path` and a specific retained `guard.anchor`.
   Prose/human lessons instead require an explicit `proseOnlyReason`. Follow the
   [classification contract](correction-coverage.md) and implement the
   [lowest feasible guard](correction-mechanization.md) in this PR.
5. Append a separate receipt for each distinct correction source, retaining the
   same classification and guard annotations for the fingerprint. If the guard
   changes, update those annotations on all of its receipts together. Preserve
   earlier source identities even after the underlying mistake is fixed.

Recurrence is derived rather than hand-maintained: one canonical URL is one
receipt per fingerprint, and repeats are distinct receipts after the first.
The [existing recurrence intake](correction-recurrence.md) files its deduplicated
mechanization task at two distinct receipts. The first receipt already requires
a guard where feasible.

Recording uses the classifier's `ruleId` as the correction identity
(`recordCorrection` in
[`packages/shared-lib/src/correction-ledger.ts`](../../packages/shared-lib/src/correction-ledger.ts)).
The first record for a rule id stays at `recurrence` 0. A later correction with
that same rule id increments that record by one and does not add a second row.
A different rule id leaves the earlier count unchanged. This step does not emit
or change checks. Coverage and the recurrence intake still derive repeat counts
from distinct source URLs per fingerprint.

For a merge conflict in the ledger, run
`node packages/shared-lib/scripts/correction-coverage.mjs --merge-ledger` before
staging it. The resolver retains receipts from both Git conflict stages and
rejects deletions or divergent edits. Resolve other files first: unresolved
guard source cannot establish valid coverage. Refused merges leave the ledger
untouched; successful resolution leaves staging explicit.

Inspect and verify the ledger from the repository root:

```sh
node scripts/correction-classifier.mjs
node --test scripts/correction-classifier.test.mjs
node packages/shared-lib/scripts/correction-coverage.mjs --base-ref origin/main
node packages/shared-lib/scripts/guard-reference.mjs --base-ref origin/main
node --test packages/shared-lib/scripts/correction-coverage.behavior.mjs
node --test packages/shared-lib/scripts/correction-recurrence.behavior.mjs
node --test packages/shared-lib/scripts/guard-reference.behavior.mjs
pnpm test --filter=@logyourbody/shared-lib
```

The classifier accepts an optional ledger path, defaults to this repository's
ledger regardless of the working directory, and validates every receipt before
writing. The pre-commit hook runs it whenever the correction ledger is staged,
then stages the classified bytes so a commit cannot land missing level or ruleId. It uses LYB-204's reviewed feasibility assessments to select the first
feasible level; incidental keywords cannot override a rejected assessment.
There is no implicit prose or human fallback for missing or malformed assessments.

The CLI delegates to `runClassifier(args, logger)`, which returns status without
changing process exit state. Git fixtures invoke the CLI for each merge scenario
and reuse this runner for repeated checks, retaining the complete assertion matrix
within the existing 30-second deadline and 100% classifier coverage gates.
Each verification batches staged and immutable parent guard blobs in one Git
process, parsing byte lengths and retaining fresh index reads on every retry.
Staged conflict resolution also batches the union's guards, including repeated
receipts, and verification reads each staged ledger snapshot only once. The
fixture generator awaits Git I/O under its existing concurrency limit.
The real Git matrix checks the process count, Unicode paths, multibyte and binary
contents, aggregate output over 1 MiB, and missing staged sources.
Verification also checks staged file modes: a symlink target containing a guard
anchor cannot establish coverage, even when the working file is regular source.

For additive ledger conflicts during a merge, run
`node scripts/correction-classifier.mjs --resolve-merge .` from the repository
root. This classifies all three immutable Git index stages and reuses the coverage
tool's `mergeCorrectionLedgers` policy. It retains incoming order and appends
branch-only receipts, allowing later main-side prepends to merge without
repeating the same conflict. It preserves independent additions and
one-sided edits, consolidates identical parent replays, rejects deletions,
conflicting duplicate identities and divergent concurrent edits, and validates
retained guards before writing the classified result. Annotation conflicts
identify the existing and incoming source receipts; review their classifications
and retained guards explicitly before retrying. Conflicting annotations are never
selected automatically.
After explicit staging, either resolver invocation verifies the staged ledger
against both merge parents without writing or restaging local edits. Missing
conflict stages for an unresolved ledger fail without writing.
Both resolver entrypoints share a preflight that refuses other unresolved Git
paths before reading guard evidence or writing the ledger. Resolve and stage
those source conflicts first, even when their files still contain guard anchors.
Review the result, stage the ledger, and run the coverage check against both
merge parents. The command leaves the index and unrelated edits untouched.

For unattended repairs, use
`node scripts/correction-classifier.mjs --resolve-merge . --stage`. This opts in
to staging only the resolved ledger after validating its classification, staged
guard sources and receipt retention against both merge parents. A failed
validation preserves the ledger and index. Retrying after staging runs the
read-only merge check; it does not restage files or overwrite unrelated edits.
Both the merge check and staged retry refuse any other unresolved Git path,
even when the staged ledger and all of its guard sources are valid.
Conflict-marker scanning disables Git color output as well as text conversion
and external diff drivers, and forces text output so binary attributes or NUL bytes
cannot conceal staged markers.
It also rejects markers shorter than seven characters.
A staged retry, with or without `--stage`, and `--check-merge` refuse any
unstaged ledger edits, including formatting changes. Review and stage those
edits explicitly before retrying; refusal preserves both the index and working
file.
If the working ledger is already valid JSON and differs from the computed merge,
both resolver entrypoints refuse to overwrite it through the same shared guard.
Review, classify and explicitly stage that manual resolution, then run
`--check-merge` to verify retention against both parents. Newly added manual
receipts survive that read-only verification. Invalid manual JSON fails without
writing or staging. An unchanged generated resolution remains safe to retry.
All three classifier verification modes require a regular staged ledger before
reading its JSON; a symlink blob cannot establish a valid resolution even when
its contents and the working file look correct. Restoring the regular index
entry permits a read-only retry.
The generated Git fixtures cover ledger marker sizes 1 and 2 in both staging
modes, alongside the staged-source marker matrix and real CLI verification.
The classifier shares the coverage resolver's recursive-ancestor reader and
normalizes identical parent replays before applying the three-way merge policy.

After staging the resolution, run
`node scripts/correction-classifier.mjs --check-merge .`. This read-only mode
verifies the staged ledger's classification, receipts and staged guard sources
against both immutable merge parents using the existing coverage nonregression
policy. It rejects a lost rule or source, a missing guard, or unclassified
metadata even when the working tree is correct. Pre-commit runs this check for
every merge, including merges whose staged ledger has no diff against `HEAD`.
An absent merge or an unstaged ledger conflict fails without writing files.

For exported parent snapshots, `node scripts/correction-classifier.mjs left.json
--merge right.json` writes the validated union to `left.json` without changing
the second input. Without a common ancestor, conflicting edits to the same
receipt require explicit resolution. The Git resolver accepts one-sided edits
only when the other parent matches the immutable common ancestor.

| Rule ID                  | Saved level | Matching rule within the reviewed feasible level                                     |
| ------------------------ | ----------- | ------------------------------------------------------------------------------------ |
| `type-or-schema`         | `codebase`  | The lesson or selected rationale names a type, schema, struct, enum or interface.    |
| `code-prevention`        | `codebase`  | Other prevention through runtime logic or API design.                                |
| `file-pattern-or-string` | `static`    | The lesson or selected rationale names a file, glob or quoted string.                |
| `ci-invariant`           | `static`    | Other deterministically checkable invariants.                                        |
| `prose-guidance`         | `prose`     | Precise guidance is feasible after codebase and static enforcement were ruled out.   |
| `human-judgment`         | `human`     | Reviewed judgment or external authority is required after all earlier levels failed. |

Lint and CI share the merged schema's `static` level. Matching considers all
distinct lessons for a fingerprint so its receipts get consistent rule IDs.
Existing levels can be promoted but never downgraded, including every guarded
entry. Repeated runs preserve unchanged file bytes. Unknown fields, levels, rule
IDs or assessment shapes fail with a diagnostic. Classification adds routing
metadata; the existing coverage check still verifies retained guard evidence
and compares it with the immutable Git base.

For new lint/typecheck/CI source checks (LYB-307), pass classified receipts to
`emitCorrectionChecks` in
[`correction-checks.mjs`](../../packages/shared-lib/scripts/correction-checks.mjs).
It emits one check per `static` fingerprint and no check for `codebase`, `prose`
or `human`. The guard must export the existing side-effect-free
`scan({ files, readSource })` interface and return `{ path, key }` findings.
The emitter routes reviewed checks; it does not translate lesson text into a
scanner or add the domain checks owned by LYB-188/189.

Run those new checks from the source repository, using a ledger containing their
classified receipts:

```sh
node packages/shared-lib/scripts/correction-checks.mjs classified-checks.json
```

The CLI reports each violation and prints the emitted checks and findings as
JSON without writing files. At zero distinct repeats, violations emit warnings
and exit 0; at one or more repeats, the same scanner emits errors and exits 1.
Clean checks exit 0 at either severity. Recurrence uses the ledger's canonical
source identity, so replaying one receipt cannot harden a check. Invalid input,
missing guards and broken scanners fail regardless of severity. Existing hard
checks retain their own invocations; guards with finding-baseline ratchets must
use the existing ratchet runner and cannot be wrapped by this emitter. The normal
shared-lib test task runs the CLI regression fixtures and emitter coverage gate.

The JSON report and existing CI/owner tables expose sources, lessons, selected
levels, guards and recurrence. Required coverage CI compares against the exact
Git base and rejects lost sources as well as lost rules or guards. It permits
lesson clarification, duplicate cleanup and guard promotion without erasing
evidence. Source linkage proves retention; actual check execution still needs
the PR's regression evidence.
