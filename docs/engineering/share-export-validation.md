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
