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
map from the merged sources. This wraps the pinned generator and refuses to
write while any other file is unmerged or a shared import fails parity. It
stages only the generated output; review the source diff before committing.

The pre-commit hook also calls this helper with `--staged` whenever a configured
source, entry point, pinned import, registry or output changes. It regenerates
from the Git index so partially staged dependency updates cannot include
unrelated working-tree edits. Pinned-source drift still fails before any write.
Bots that do not run hooks must invoke the helper or generator before submitting
their update; the required CI parity check remains read-only.

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
