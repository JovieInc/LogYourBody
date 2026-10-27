# Automatic correction guards (LYB-208)

Cloud agents handling LYB corrections implement the lowest feasible guard in the
same PR, starting at the first receipt. Keep the source, ordered feasibility
assessment, and specific guard anchor in the existing
[`corrections.json`](../../packages/shared-lib/corrections.json) ledger. A
codebase fix takes precedence over lint/test/CI where it can prevent the full
mistake by construction. Add a failing-then-passing regression, wire the guard
into the relevant required check, and retain the original product scope.
The [coverage check](correction-coverage.md) already rejects a mechanizable receipt
without a retained guard. Source anchors still do not prove execution: the PR
must supply actual check evidence. The [recurrence intake](correction-recurrence.md)
remains a backstop after two distinct receipts, not a reason to defer a guard.

New source policies can start with existing violations. Add a warning and a
baseline for those findings; reject new violations from the first run. Do not
turn existing security, privacy, auth, billing, data, native evidence, or other
hard gates into warning-only checks. Prefer an existing suitable guard over
creating a parallel implementation.

For a deterministic source scanner, add an optional `ratchet` to its existing
ledger guard. Example (illustrative, not an installed guard):

```json
{
  "path": "packages/shared-lib/scripts/example-guard.mjs",
  "anchor": "reject the complete forbidden import",
  "ratchet": {
    "baseline": "packages/shared-lib/example-guard-baseline.json"
  }
}
```

The guard module exports a side-effect-free `scan({ files, readSource })`
function (async is supported). It returns an array of `{ path, key }` findings:

```js
export function scan({ files, readSource }) {
  // reject the complete forbidden import
  return files
    .filter((path) => path.startsWith('apps/') && path.endsWith('.example'))
    .flatMap((path) =>
      readSource(path)
        .split('\n')
        .filter((line) => line.startsWith('forbidden import '))
        .map((line) => ({ path, key: line.trim() })),
    );
}
```

Use only the supplied source snapshot, not direct filesystem/Git reads, network,
secrets, or current-worktree imports to determine findings. The same scanner
runs on both the working tree and immutable Git source when establishing a new
rule. Keep the scanner import side-effect-free; the runner imports it to call
`scan`. Cover real violating and permitted inputs in its behavioral tests.

A key identifies the complete normalized violation, including relevant actual
and expected values. Exclude incidental line numbers so harmless line shifts do
not create new debt. Repeated identical findings count separately. Do not store
source secrets or customer data in keys. Paths are repository-relative; separate
fingerprints cannot share a baseline. Duplicate receipts must agree on ratchet
metadata as well as classification and guard anchors.

Run from the repository root:

```sh
# Resolve a corrections.json conflict from Git's base/ours/theirs index stages.
# Retains incoming order, validates coverage, and leaves review/staging explicit.
# Deletions or divergent edits fail without writing; resolve those manually.
node packages/shared-lib/scripts/correction-coverage.mjs --merge-ledger
# Seed a new baseline, or remove findings fixed in this PR (review the diff).
node packages/shared-lib/scripts/correction-ratchet.mjs --base-ref origin/main --update-baselines
# Read-only verification, using the PR's exact base SHA in CI.
node packages/shared-lib/scripts/correction-ratchet.mjs --base-ref origin/main
node --test packages/shared-lib/scripts/correction-ratchet.behavior.mjs
pnpm test --filter=@logyourbody/shared-lib
```

Merge readiness inspects staged changes without external diff or text conversion
drivers, so a presentation filter cannot hide unresolved conflict markers.

Baselines have schema `lyb.correction-ratchet/v1` and a `findings` array. Seeding
requires a readable immutable base: findings introduced by the PR cannot be
grandfathered. For an existing rule, CI compares the head baseline with the
baseline at that Git revision. Baseline edits, moves, changed values, added
occurrences, and new files cannot spend another finding's allowance. Removed
ratchets, malformed evidence, missing baseline files, broken scanners and
symlinked guard/baseline paths fail closed. Baseline updates validate every rule
before writing. Resolved findings must be removed immediately, so a later PR
cannot reintroduce them under stale allowances. At zero findings the rule is
strict. Existing accepted findings emit a GitHub warning and count in the job
summary; a successful run never rewrites files.

The existing required CI change-detection job executes all registered ratchets
on every diff, including docs-only PRs and merge groups, using the exact PR,
merge-group, or preceding-main base already fetched for coverage. The normal
shared-lib suite runs the runner's behavioral tests with coverage. This adds
no scheduler, cloud account, API credential, or model-driven CI decision.

The existing Native Merge Queue Enrollment workflow automatically enqueues every
eligible same-repo, non-draft PR to main after CI passes on its exact head. Keep
that automatic path on; all required checks, deployments and queue rules still
apply. When the lanes harness owns pushing and PR creation, hand it the commits
and validation evidence. Do not enable the retired Codex Auto-Fix workflow or
start a second PR owner.

For merge repairs, `node scripts/correction-classifier.mjs --resolve-merge . --stage`
merges and classifies the correction ledger after other conflicts are resolved.
The shared readiness check also rejects newly added conflict markers in the index,
including diff3 base markers, before writing or staging the ledger. The pre-commit
`--check-merge` path and staged retries use the same check; cleaning only the working
file cannot hide an unresolved staged source. Resolve and stage the source, then
retry the same command. Unrelated unstaged edits remain untouched.

The staged-marker check forces text output even for paths marked binary by Git
attributes. Binary classification, text conversion and terminal color cannot hide
new conflict markers from the resolver or the pre-commit merge verifier.
