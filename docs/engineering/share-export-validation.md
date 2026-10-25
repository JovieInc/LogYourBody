# LYB-40 share export validation

The export coordinator freezes payload, format, all content options and renderer
revision. Each sheet owns at most one worker task and one temporary PNG. It keeps
at most 128 small save receipts with weak photo references; it retains no rendered
image cache. A successful save of the same content is acknowledged without another
Photos transaction. Failed attempts can retry. Cancelled system shares can reopen.

`responsive_share_export` is a positive Statsig gate, default off through the
existing analytics port, for the new inline status and accessibility announcements.
The stale-input, duplicate-write, ownership and confirmed-result guards apply to
every export. Enable the gate for reference-device acceptance. Navigation, Close,
format and privacy controls stay available during preparation and saving.

Photos uses add-only authorization and waits for `performChanges` completion.
The adapter presents no alerts. Denial offers Settings or Share; restriction and
write failure have distinct messages. A submitted Photos transaction cannot be
recalled. If inputs change or the sheet closes after submission, its receipt is
retained to prevent a duplicate retry, but its late UI completion is suppressed.
Activity completion means the system activity reported completion, not proof of
delivery to a remote recipient.

The worker actor prepares opted-in photos at export size and performs PNG encoding,
file writes and deletion. Hidden photos never reach capture. SwiftUI ImageRenderer
capture and system presentation remain on MainActor. Avatar asset decoding still
belongs to the measured capture interval. No claim about hang duration or speed is
inferred from the use of an actor or Task.

## Native execution

`BodyScoreShareExportTests` is a normal member of `LogYourBodyTests` and is not
excluded from `TestPlans/Unit.xctestplan`. The repository's existing Unit runner
(`bundle exec fastlane ios ci_test_unit`) must produce exact-head execution and
coverage receipts. Preserve the existing same-selector coverage baselines.
The added cases cover delayed/failing preparation, render and encoding errors,
rapid double taps, payload/format/privacy edits, dismissal during encoding,
noncancellable save completion, Photos permission/ownership/write outcomes,
successful saves, system-share cancellation/completion/failure, file cleanup,
rendered-buffer release and actual PNG OCR after value/privacy changes.

Also run the existing BodyScoreShareCardTests and share UI cases through the
launch-quality runner. Record the named passing cases and attach the retained
synthetic PNGs from the xcresult. Confirm VoiceOver announcements, Dynamic Type,
Settings recovery, interactive system-share dismissal, Close during work and
format/privacy changes on the actual screen.

## Reference-device performance acceptance

Proposed reference: physical iPhone 16, iOS 26, Release configuration. Record the
actual model, OS version, build SHA, gate configuration, thermal state and fixture
dimensions with every receipt. No device was available on the Linux implementation
host, so this reference has **not** been measured or certified.

Use Instruments Points of Interest, Time Profiler, Hangs and Allocations. Filter
the `com.logyourbody.app` / `ShareExport` signposts:

- `ImagePreparation`: worker preprocessing and target-size thumbnail preparation.
- `MainCapture`: creation of ImageRenderer and synchronous `uiImage` capture.
- `EncodeAndWrite`: worker PNG encoding and protected temporary-file write.
- `TapToFeedback`: accepted tap to SwiftUI status appearance callback. The callback
  is a scheduling probe, not proof that pixels have reached the display. Dismissal
  also closes any outstanding interval; exclude those samples.

Capture at least 100 Save/Share taps across score-only, opted-in photo, avatar,
all-metric and contextual fixtures at every aspect, including cold/warm trials.
Use event timestamps and display/video or frame instrumentation to measure the
first visible/accessible acknowledgement. Report p50/p95/max and the sample count;
the required displayed-feedback p95 is <100 ms. Correlate the callback probe with
those frame measurements instead of accepting it alone. Check peak memory and
post-dismissal recovery while rapidly editing and tapping against delayed adapters.

Compare with source baseline `c99f4da73` (which contains the reported synchronous
capture and unconfirmed Photos submission). Instrument that baseline's image
preparation and render interval with the same phase names in an isolated profiling
build. Attach **both** .trace files and their summaries privately. No before/after
Instruments captures, exact-head native test/coverage receipts, or latency numbers
are present from this Linux host; these acceptance items remain unverified.

## Scope and handoff

JOV-6087 / LYB-39 was read before editing; it is in progress. Card artwork,
geometry, typography and export dimensions are unchanged here. Coordinator and
tests live in separate files; the only card-file edits concern export lifecycle,
feedback and dismissal. Reconcile that editor wiring when integrating concurrent
LYB-39 changes. No founder screenshots or real health/profile data are included.

Local verification used Node 22.23.2 and pnpm 10.34.1. Root lint, typecheck and
tests passed (Turbo reused cached results; the shared-lib test suite was also
executed with subprocess access). Changed-file strict SwiftLint reported zero
violations; five SourceKit-dependent rules are unavailable on Linux. The full
`pnpm lint:swift` scan also found zero violations but exited unsuccessfully when
its cache write to read-only `/var/tmp/SwiftLint` failed. `xcodebuild -version`
failed because Xcode is absent. Registry checks, correction coverage/ratchets,
source projection and whitespace checks were run separately. These are source
checks, not native execution receipts.

GBrain search, write to `lyb-40-share-export-lifecycle`, and readback all failed
with connection refused at `127.0.0.1:7801`. No durable write/readback is claimed.

## PR #1532 repair evidence

`git merge --no-edit origin/main` reported already up to date at `c99f4da73`.
`gh run view 40151321879 --repo JovieInc/LogYourBody --log-failed` identified
the thumbnail's pixel/point mismatch and the diagnostic fixture's project hash
mismatch. The worker now converts export pixels to source-image points. Native
tests retain the failing file-cleanup case and add all export aspects at 1x/2x/3x,
checking backing pixel dimensions and expected aspect-fit resolution.

The routing positive fixture uses compressed project bytes from the original
policy-pinning commit `45d5dd3384b907a40352028c0a1b5404f27e03fd`, checked against
the unchanged workflow digest. A changed-project refusal case runs the real
trusted CLI without reaching any native tool. No workflow or gate was changed.

On the Linux repair host, Node 22.23.2/pnpm 10.34.1 ran
`bash scripts/codex-setup.sh --run lint`, `--run typecheck`, `--run test`, and
`--run product:check` successfully. Turbo reused unaffected package results;
shared-lib tests executed after rerunning with subprocess access because the
sandbox denied process creation. Changed-file strict SwiftLint with `--no-cache`
passed with its five Linux SourceKit rules unavailable. Correction coverage,
correction ratchets, repository source parity and `git diff --check` passed.

`python3 -m pytest -p no:cacheprovider scripts/tests/test_runner_routing.py -q`
reproduced 1 failure/40 passes before repair and passed all 41 afterward. Running
the same command under CI's bashcov 4.0.0 and then
`python3 scripts/tests/test_runner_routing.py` passed all four 80% coverage floors:
93.48%, 82.50%, 90.62%, 90.91%. Local Ruby was 3.2.3; CI uses Ruby 4.0.
`xcodebuild -version` failed because Xcode is absent. Repaired native tests,
native coverage, Launch Quality and physical-device acceptance remain unverified.
GBrain write and readback for `lyb-40-pr1532-repair` both failed with connection
refused at `127.0.0.1:7801`; no durable persistence occurred.

## PR #1532 aspect-fit repair

Merged `origin/main` at `0c82e0c81` without conflicts in merge commit `40577f07e`
before editing. The harness checkout was detached and the original branch was
occupied by another worktree, so local work uses `fix/lyb-40-pr1532-repair`.
No push or PR mutation is part of this repair.

`gh run view 40154055343 --repo JovieInc/LogYourBody --log-failed` found nine
assertion failures in `testPreparationBoundsPixelsAcrossSourceScalesAndExportAspects`:
story thumbnails were 1280x1920 rather than 1080x1620 inside 1080x1920 bounds,
at all three source scales. CI Summary failed because Launch Quality failed.
The worker now requests the photo's explicit minimum-ratio fitted size after
pixel-to-point conversion. The retained regression keeps every pixel-bound and
exact-fit assertion, adds landscape sources, and covers an empty opted-in image
as a render failure. The correction ledger records the CI receipt and guard.

On this Linux host, Node 22.23.2/pnpm 10.34.1 ran
`bash scripts/codex-setup.sh --run lint`, `--run typecheck`, `--run test`, and
`--run test --filter=@logyourbody/shared-lib` successfully. The isolated shared-lib
suite executed 156 Vitest tests and 122 Node tests. Its correction coverage test
retained all configured coverage floors. The first root test attempt hit sandbox
subprocess restrictions; the unrestricted retry had one correction-coverage test
timeout before the isolated suite passed. The final root retry passed all eight
Turbo tasks (six cached), including the web build and tests. No timeout or gate
was changed. The marketing asset generator's timestamp-only side effect was
discarded.

Changed-file `swiftlint lint --strict --no-cache --config apps/ios/.swiftlint.yml`
passed for the worker and native test file with zero violations; five
SourceKit-dependent rules were unavailable. Correction coverage, correction
ratchets, all 29 correction behavioral tests, repository source parity and
`git diff --check` passed, using:

```sh
node packages/shared-lib/scripts/correction-coverage.mjs --base-ref origin/main
node packages/shared-lib/scripts/correction-ratchet.mjs --base-ref origin/main
node --test packages/shared-lib/scripts/correction-coverage.behavior.mjs packages/shared-lib/scripts/correction-ratchet.behavior.mjs
python3 scripts/repository_docs.py
git diff --check
```

`xcodebuild -version` returned command not found;
repaired native execution, coverage, Launch Quality and device acceptance remain
unverified until the harness runs the required checks.

GBrain search, write to `lyb-40-pr1532-aspect-fit`, and readback failed with
connection refused at `127.0.0.1:7801`. No durable write/readback occurred.

## PR #1532 main-conflict repair

Merged `origin/main` at `1572e8e991d480f768510a6eb8ecb727a530e2c5` in
`42ad0ad312d5407b8ad69e018e3558dbbc04e315` before follow-up repairs. Resolved the
correction ledger by retaining every receipt from both branches, and regenerated
the repository source map from the merged Xcode project. Both share-export and
delegated-training target memberships are present. The share implementation and
its native tests retain their prior contents.

Main refreshed the reviewed diagnostic project pin in
`203aecb854b8e256c7115ab4ae7b77e3f2b8f67e`. The existing routing regression then
failed with 40 passes and one fixture-digest failure. Refreshed the compressed
offline fixture from that exact commit and updated its provenance comment.
Its decompressed SHA-256 is
`5ecaca52c8447cb1af53c8a662b61e0551c311aa9716d25801e2fd01e2ed306d`, matching
the inherited policy. The merged live project has a different digest, so it
cannot substitute for the reviewed fixture. All seven pins, the digest assertion,
and every admission/refusal case remain enforced. The correction ledger records
the regression. No workflow changes were made beyond merging main.

On Node 22.23.2/pnpm 10.34.1, these commands passed:

```sh
bash scripts/codex-setup.sh --run lint
bash scripts/codex-setup.sh --run typecheck
python3 -m pytest -p no:cacheprovider scripts/tests/test_runner_routing.py -q
node packages/shared-lib/scripts/correction-coverage.mjs --base-ref origin/main
node packages/shared-lib/scripts/correction-ratchet.mjs --base-ref origin/main
python3 scripts/repository_docs.py
git diff --check
```

Routing passed all 41 cases. The same pytest command under bashcov 4.0.0 followed
by `python3 scripts/tests/test_runner_routing.py` passed all four 80% floors:
93.48%, 82.50%, 90.62%, 90.91%. Ruby was 3.2.3; CI uses Ruby 4.0.
Correction coverage reported 20/20 mechanized rules; existing ratchet allowances
were preserved. The initial ratchet attempt needed subprocess access after
`spawnSync git EPERM` in the sandbox.

Broader validation attempted `bash scripts/codex-setup.sh --run test` and
`bash scripts/codex-setup.sh --run test --filter=@logyourbody/shared-lib`.
The sandbox denied subprocess creation. Unrestricted retries hit unrelated
timeouts. Retried the root test with `taskset -c 0,1` and the filtered test with
`taskset -c 0-3`, each prefixing the same command above. The last filtered run
passed 154/156 tests; `correction-coverage.test.ts` and
`web-surface-cleanup.test.ts` exceeded the unchanged 5-second outer timeout.
The full root suite is therefore **not verified green** on this host.
The correction suite itself passed all 33 cases with 100% line, branch and
function coverage using its normal inner command:

```sh
node --test --experimental-test-coverage \
  --test-coverage-include=packages/shared-lib/scripts/correction-coverage.mjs \
  --test-coverage-include=packages/shared-lib/scripts/correction-coverage-owner.mjs \
  --test-coverage-include=packages/shared-lib/scripts/correction-ratchet.mjs \
  --test-coverage-include=packages/shared-lib/scripts/jovie-separation.mjs \
  --test-coverage-include=.github/scripts/lib/linear-correction-coverage.mjs \
  --test-coverage-lines=90 --test-coverage-branches=85 --test-coverage-functions=100 \
  packages/shared-lib/scripts/correction-coverage.behavior.mjs \
  packages/shared-lib/scripts/correction-ratchet.behavior.mjs \
  packages/shared-lib/scripts/jovie-separation.behavior.mjs
```

No assertion, timeout or coverage gate was changed. Discarded only the web
build's generated marketing-asset timestamp changes.

`gh run view 40158507283 --repo JovieInc/LogYourBody --log-failed` reported that
the current-head run was still in progress. GitHub reported no failed checks;
Launch Quality was pending. Read the last completed failure with
`gh run view 40154055343 --repo JovieInc/LogYourBody --log-failed`; its thumbnail
assertion failures are the prior aspect-fit repair described above.
`xcodebuild -version` returned command not found. Native execution, coverage and
physical-device acceptance remain unverified on this Linux host.

The checkout was detached, so the repair uses local branch
`fix/pr1532-main-conflict-20261025`. The harness owns pushing and PR updates.
GBrain search, write to `lyb-40-pr1532-main-conflict-20261025`, and readback all
failed with connection refused at `127.0.0.1:7801`; nothing was persisted.
