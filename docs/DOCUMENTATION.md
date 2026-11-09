# Documentation ownership and parity

The repository owns README/AGENTS, local manifests, runtime declarations and
release workflows. [The portable company contract](company/REPOSITORY_SOURCE_CONTRACT.md)
is shared source policy; it does not change the local stack or release gates.

`repository-docs.json` selects source-owned entry points, local manifests and
workflows, generated output and immutable shared imports. The generated
[repository source map](REPOSITORY_SOURCES.md) renders package facts directly and
fingerprints other sources. Review related prose whenever a fingerprint changes.
This is source evidence, not proof of deployment, current credentials or runtime.

From the repository root (Python 3.9+; no network or secrets):

```sh
python3 scripts/repository_docs.py
python3 scripts/repository_docs.py --write
```

Use `--write` after reviewing local source changes. Shared-file edits belong in
the canonical repository named by each import, followed by a reviewed full Git
revision and SHA-256 update. From the reviewed JovieInc/ci tooling checkout:

```sh
python3 scripts/repository_docs.py --root /path/to/this-repo --write \
  --upstream JovieInc/ci=/path/to/ci \
  --upstream JovieInc/Jovie=/path/to/Jovie
```

After merging a branch, resolve source conflicts first, then run
`python3 scripts/resolve-repository-docs.py` to regenerate and stage the source
map from the merged sources. A conflicted map is rebuilt from the merged index,
so unstaged source edits and either parent projection cannot change its
fingerprints. This wraps the pinned generator and refuses to write while any
other file is unmerged or a shared import fails parity. It stages only the
generated output; review the source diff before committing.

When a merged Xcode project changes the diagnostic workflow's exact project pin,
stage the merged project and pass its digest. The resolver keeps branch workflow
lines, a one-sided reviewed audit pin, and dependency lines added by only one
parent. Divergent audit pins also need `--reviewed-audit-sha256`. It writes
those pins and rebuilds a conflicted source map from the index, ignoring
unstaged source bytes. It refuses a digest that does not match the staged
project or audit, a merged project that dropped a parent file membership or
changed a new parent build-file mapping, any other workflow difference, and
every other unmerged path.

```sh
python3 scripts/resolve-repository-docs.py \
  --reviewed-project-sha256 <reviewed-merged-project-sha256> \
  --reviewed-audit-sha256 <reviewed-merged-audit-sha256>
```

Staging the workflow yourself, with one project-pin line, still works. This
explicit mode verifies the supplied digest against the staged project, refuses
unstaged edits, symlinks, conflict markers and ambiguous pins, and stages only
the updated workflow and source map. Other diagnostic pins and all trust checks
remain intact. Ordinary repair and commit hooks never grant this review.

The pre-commit hook runs `python3 scripts/resolve-repository-docs.py --staged`
after formatting and correction classification, and before the merge ledger
check. It refreshes the projection from indexed sources, preserves unstaged
source edits, and refuses unstaged projection edits or pinned-source drift.
Bot commits created outside local hooks still need this refresh during repair;
CI continues to reject stale output.

When the generated source map and correction ledger both conflict, resolve and
stage the source inputs, then run the same `--staged` command before the ledger
resolver. Pre-commit uses that order so a conflicted projection cannot make the
ledger check fail closed before the projection is rebuilt. It rebuilds only the
conflicted projection from stage-zero inputs and leaves unrelated conflicts
untouched. A conflicted input still fails without changing the projection or
index; ordinary unstaged projection edits remain protected.

For dependency bumps with an already updated lockfile, run
`python3 scripts/resolve-repository-docs.py --verify-lockfile`. It verifies the
existing lockfile with pinned Corepack pnpm (frozen, offline, lockfile-only,
lifecycle scripts disabled) before regenerating and staging only the source map.
It retains the refusal of unstaged dependency/output edits and pinned-source drift
without re-resolving unrelated dependencies.
Both dependency modes also require staged `repository-docs.json` changes before
invoking pnpm, keeping parity checks and output selection on reviewed configuration.
Both dependency modes render the source map from the Git index, preserving
unrelated unstaged source edits without fingerprinting them. Refresh mode stages
the lockfile and projection together; verify mode stages only the projection.

For dependency PRs, stage the reviewed manifests and run
`python3 scripts/resolve-repository-docs.py --refresh-lockfile`. This explicit
repair first verifies the existing lockfile offline with pinned Corepack pnpm.
Only a confirmed manifest mismatch (`ERR_PNPM_OUTDATED_LOCKFILE`) triggers
regeneration without lifecycle scripts and a second frozen offline check.
Valid lockfiles keep their resolutions; other installation failures stop repair.
Both dependency repair modes refuse index or manifest edits made while pnpm is
verifying inputs. They preserve those edits and restore the original generated
artifacts; stage the reviewed inputs and retry the same command.
Staged projection generation also rechecks the index before writing. Dependency
repair carries the verified index through rendering, so an observed concurrent
staged edit cannot leave the source map describing an older manifest. Review the
changed inputs and retry; the other writer's staged edit remains intact.
Both dependency modes also compare the verified lockfile bytes after rendering
and before writing or staging artifacts. Lockfile changes during rendering refuse
repair and restore the original artifacts; retry uses the reviewed inputs.
Tracked dependency edits during rendering also refuse repair before artifact
writes or staging. The edits remain available for review; stage them and retry
the same command.
New untracked or ignored dependency inputs created during verification or rendering
also refuse artifact staging. Review and stage those inputs before retrying;
installed dependencies and Next.js build output remain excluded.
Frozen verification also refuses lockfile changes before regenerating or staging
the source map. Only a confirmed outdated lockfile permits refresh mode to write
new resolutions; retrying after a refusal uses the original reviewed artifacts.
If resolution, frozen verification, projection generation or Git staging fails,
the helper restores the original lockfile and projection bytes (or absence) so
the same command can be retried without manual cleanup. Another writer's index
lock and unrelated edits remain untouched.
It then stages the lockfile and source map, refusing unresolved source conflicts,
unstaged dependency or projection edits, untracked dependency inputs, and pinned-source drift. It requires registry
access for uncached resolutions; commit hooks and CI keep frozen installation.
Both dependency modes also refuse ignored npmrc files, pnpm hooks and patches;
configuration inside installed `node_modules` and generated `.next` build output
is excluded from this preflight. Next.js-generated manifests are preserved.
Both dependency modes check pnpm hooks (`.pnpmfile.cjs`), workspace `.npmrc`
files and `patches/` as dependency inputs. Stage reviewed changes to these files
before repair; local edits remain untouched when the preflight refuses them.
Both modes refuse indexed symlinks before invoking pnpm; dependency inputs must
be regular indexed files, including executable hooks.

The default check verifies local copies against declared hashes offline. It does
not claim that upstream pins are latest. Update-time Git readback verifies the
exact upstream bytes. Only listed imports and generated output are written;
README/AGENTS remain local. Review changes in a separate PR per repository.
Revert the consumer commit to restore its previous pin; siblings remain usable.

CI runs the same deterministic parity tests and coverage as shared tooling in
the nonblocking shadow workflow. Detect Changes also runs
`python3 scripts/repository_docs.py` with no `continue-on-error` on every pull
request, merge group, and main push. CI Summary fails when that job fails, so a
stale projection cannot merge. CI Summary remains the only required status
check; this adds no branch-protection context. The shadow check is unchanged.
JOV-6607 tracks qualification;
JOV-6555 owns shared-CI release distribution and updater integration. Promote only
with representative ship samples, correctness/pass rate, p95, throughput/cost,
failure isolation, an accountable owner and tested rollback. No approved numeric
promotion threshold is implied. No scheduler, new bot or paid service is added.
