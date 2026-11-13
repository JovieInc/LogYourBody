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
# After a merge conflict, preserve receipts from both immutable parents.
node packages/shared-lib/scripts/correction-coverage.mjs --base-ref <prior-head-sha> --base-ref <merged-main-sha> --output coverage/corrections/coverage.json
node --test packages/shared-lib/scripts/correction-ratchet.behavior.mjs
pnpm test --filter=@logyourbody/shared-lib
```

After reviewing a launch-audit change, stage `scripts/ios/launch-quality-audit.sh`
and run `python3 scripts/resolve-repository-docs.py --reviewed-audit-sha256 <reviewed-digest>`.
The existing repair entrypoint updates the diagnostic workflow pin and all routing
regression pins together. It refuses a digest that differs from the staged audit,
unstaged inputs, symlinks, conflicts, and missing, duplicate or divergent pins.
Review and stage its output explicitly; source-map regeneration remains in the
normal pre-commit path. This command never grants trust from candidate bytes alone.

Merge readiness inspects staged changes as text without external diff or text
conversion drivers, so binary attributes and presentation filters cannot hide
unresolved conflict markers.

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

Refresh shared company workflow pins with the existing policy verifier:

```sh
node .github/scripts/verify-merge-queue-policy.mjs --refresh-company-pins
```

It reads GitHub through `gh api`, resolves upstream main once, and selects the
latest commit touching the shared drift check's canon, guard or workflow paths.
Before writing, it verifies that this commit contains exactly the same guard
and canon trees as upstream main. Certification retains main's latest kit.
The callers may therefore have different immutable SHAs: a certification-only
commit is absent from the drift check's filtered history and would falsely fail.
Missing history, incomplete trees, lost guard changes and ambiguous caller pins
refuse without changing either workflow. The required policy suite tests this
selection and its refusal paths. Review and stage both outputs explicitly.

The existing Native Merge Queue Enrollment workflow automatically enqueues every
eligible same-repo, non-draft PR to main after CI passes on its exact head. Keep
that automatic path on; all required checks, deployments and queue rules still
apply. When the lanes harness owns pushing and PR creation, hand it the commits
and validation evidence. Do not enable the retired Codex Auto-Fix workflow or
start a second PR owner.

For merge repairs, `packages/shared-lib/corrections.json` uses the
`correction-ledger` merge driver. `scripts/codex-setup.mjs` installs
`merge.correction-ledger.driver` as
`node scripts/correction-classifier.mjs --merge-driver %O %A %B`.
That command classifies the same parent union as `--resolve-merge`: incoming
receipt order, then branch-only receipts. Divergent edits of one receipt stay
conflicted. A checkout without the driver keeps Git's text merge.
For launch-route conflicts, `python3 scripts/resolve-repository-docs.py --union-manifests`
also unions the canonical launch binding arrays and rejects lost or reordered
parent selectors. It leaves a conflicted generated manifest untouched. Regenerate
that manifest with `node scripts/lyb-launch-manifest.mjs scripts/fixtures/lyb-launch-route-bindings.json`,
review and stage both files, then continue the existing pin and ledger repair.
The staged source-map check verifies the same parent binding inputs.

For merge repairs, `node scripts/correction-classifier.mjs --resolve-merge . --stage`
merges and classifies the correction ledger after other conflicts are resolved.
`python3 scripts/resolve-repository-docs.py --merge-sections docs/<path>.md`
prints a proposal retaining both parents' independent paragraph insertions, or
new incoming standalone sections. Review and stage the proposal explicitly;
it leaves working files and the index untouched.
`python3 scripts/resolve-repository-docs.py --union-manifests` keeps every parent
test input while a diagnostic workflow pin conflict remains. The reviewed project
digest resolver replaces that pin and then rebuilds the source map.
When the remaining conflicts are the ledger and generated source projection, run
`python3 scripts/resolve-repository-docs.py --merge-ledger` to refresh the projection
from staged inputs and invoke that same parent-preserving classifier. It refuses
other source conflicts and missing merge parents before writing. A classifier
refusal restores the projection bytes and index stages; resolve the reported
source or guard problem and retry. Unrelated unstaged source edits stay untouched.
When the diagnostic project pin also conflicts, combine `--merge-ledger` with
`--reviewed-project-sha256 <reviewed-merged-project-sha256>` (and an explicit
`--reviewed-audit-sha256` when needed). The command requires an active merge,
uses the existing reviewed pin resolver to retain one-sided parent dependency
hash updates, then preserves both parents' receipts.
It never derives a trust digest. If receipt validation refuses after pin repair,
the reviewed pin remains staged; resolve the reported problem and retry.
Union generation and parent verification share guard snapshots within that command;
each retry reads the index and guard sources afresh.
If the staged index changes during projection rendering, refusal preserves the
other writer's projection bytes and index entries; rollback begins only after
the resolver completes its own render. Review the inputs and retry.
If ledger validation then fails, rollback also verifies that the rendered projection
bytes and index entry are unchanged. Concurrent working or staged projection edits
remain intact; review and stage the inputs before retrying the same command.
Rollback also checks the rendered file's mode, inode and device without following
links. A concurrent replacement, symlink or permission change refuses rollback
even when the projection bytes match, preserving the other writer's file and index.
The reviewed diagnostic project-pin resolver also retains each newly added parent
file's group and build-phase references; retaining a declaration alone is insufficient.
For a documentation rewrite conflicting with incoming new sections, run
`python3 scripts/resolve-repository-docs.py --merge-sections docs/path.md`.
It prints a proposal from the three unmerged index stages, preserving the branch
and appending distinct incoming level-two sections. Review the proposal, replace
the conflicted file and stage it explicitly. This mode never writes or stages;
it refuses incoming edits/deletions, duplicate headings, unheaded additions and
non-documentation paths. It does not adjudicate contradictory prose.
For a conflicted Xcode project whose parents only insert file membership, run
`python3 scripts/resolve-repository-docs.py --union-project`.
It stages those insertions from both parents and refuses an edit or deletion of
an existing line. Review the staged project, then pass its digest to
`--reviewed-project-sha256`. The union never derives that digest.
The same command verifies an automatically merged, stage-zero project against
the immutable additive parent union without changing files or the index. It
refuses a different staged result or unstaged project edits.
Before regenerating the staged source map, the resolver also requires one
diagnostic project pin matching the indexed Xcode project. Stale, missing or
duplicate pins refuse without writing. Review the project diff, then use
`--reviewed-project-sha256` with the reviewed digest; unstaged pin edits do not
repair the commit.
The pin resolver retains independent workflow edits from either parent when
the other changed only the project pin, verifying that the working conflict
contains only that pin and matches the retained parent outside it.
Repair a conflicted source projection first with
`python3 scripts/resolve-repository-docs.py --staged`. If staging fails, it restores
the original projection bytes (or absence), so the same command remains retryable.
Index snapshots admit only regular stage-zero registry, entry-point, fingerprint
and imported-source files, including executable files. Symlink blobs fail before
the projection or index changes, even when the worktree contains regular bytes.
When the merged `project.pbxproj` is already stage zero and the diagnostic workflow
conflicts only on its project pin, pass the reviewed digest of that staged project:
`python3 scripts/resolve-repository-docs.py --reviewed-project-sha256 <digest>`.
The command writes that pin, rebuilds a conflicted source projection from the index,
and leaves the correction ledger untouched. It refuses any wider workflow conflict,
a digest that does not match the staged project, a dirty project, and a hand-edited
workflow. It never derives the digest. Resolve the ledger afterwards.
The shared readiness check also rejects newly added conflict markers in the index,
including diff3 base markers, markers shorter than seven characters, and files
marked binary by Git attributes, before
writing or staging the ledger. When that ancestor stage contains conflict markers
from a recursive merge, both resolver entrypoints rebuild it from the two real
merge bases and their shared parent before applying the same union. The pre-commit
`--check-merge` path and staged retries use the same check; cleaning only the working
file cannot hide an unresolved staged source. Resolve and stage the source, then
retry the same command. Unrelated unstaged edits remain untouched.

Recursive reconstruction reads each immutable guard blob once per resolution;
the cache ends with that invocation, so retries never reuse mutable index evidence.

The combined `--merge-ledger` repair also checks that the source index stays
unchanged between projection rendering and ledger classification. A concurrent
source change refuses success without reverting the reviewed source or classified
ledger; rerun the same command to rebuild fingerprints from current staged inputs.

The readiness check forces text inspection even when Git attributes mark a staged
file as binary, so those attributes cannot conceal unresolved conflict markers.
It accepts up to 16 MiB of staged diff output, including markers at the end of a
large merge, and refuses larger output rather than inspecting a truncated diff.
Both resolver modes require an active merge before writing; conflicted cherry-picks
are refused without changing the ledger or index.

With `--stage`, guard validation reads the Git index throughout resolution, so
unrelated working edits cannot invalidate the reviewed staged snapshot. The
unstaged resolver continues to validate guards from the working tree.
Staged verification accepts only regular indexed guard files (including executable
files); a symlink blob cannot supply guard evidence, even when its text matches
the anchor and the working file is regular. The batched blob reader enforces file
modes for final verification and staged retries. Unstaged guard text or symlinks
cannot change the reviewed staged snapshot. Refusal preserves the ledger and index.
Both resolution modes and staged verification refuse an index that changes during
validation, before writing the ledger or returning success. Retry the same command
against the current index; the refusal preserves the other writer's staged changes.

The classifier also snapshots the working ledger and rechecks its bytes after
validating the index and both merge parents, and again immediately before
replacing the file. An edit during validation or in that pre-write window
refuses resolution, staging and a successful verification verdict without
overwriting the other writer. Review the working ledger and retry against the
current merge. Concurrent ledger edits are preserved and cannot be overwritten
by a resolution computed from earlier bytes.
They also recheck `HEAD` and `MERGE_HEAD` before writing or returning success;
changed parents invalidate the review even when the index is unchanged.
The pre-write boundary samples the index, then repeats the index, parent and
ledger comparison before replacement. A writer that lands during that sample
cannot authorize the write, staging or a successful verdict.
