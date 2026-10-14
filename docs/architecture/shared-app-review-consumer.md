# Shared App Store review consumer

LogYourBody composes its manual check-in persistence owner, the canonical
JovieKit `AppReview` policy, the existing Statsig port and Apple's StoreKit scene
API. LYB does not maintain eligibility, cooldown, rolling budgets, assignment or
ledger encoding independently. The feature remains default off and is separate
from TestFlight delivery.

## Canonical source and updates

The materialized package is `apps/ios/Vendor/JovieKit`, product/module `JovieKit`,
AppReview schema version 1. Xcode uses `XCLocalSwiftPackageReference` with the
relative path `Vendor/JovieKit`. It does not clone the Jovie monorepo or depend
on a developer checkout.

`apps/ios/Vendor/JovieKit.source.json` pins canonical policy/source revision
`2fec0fe05f95e454da24cb6a9fd7021501ca414b` in `JovieInc/Jovie`. The importer and
manifest originate at distribution revision
`1e6c7f11ef1cc4fb64c59c1b1758d823e8c6bc48`. `repository-docs.json` records the
upstream path, full revision and SHA-256 for the tool, manifest, generated receipt
and every package file. The package retains the upstream proprietary license.

The checksum-verified importer downloads only immutable HTTPS source, verifies
all files before materializing them, rejects an existing destination, and never
executes downloaded code. It works under LYB's existing Node 22 runtime. Swift
requirements remain tools 6.0, language 5, iOS 18+; LYB's iOS 26 target is unchanged.
No third-party package, account, credential, service or registry is added.

From the repository root, validate the committed snapshot offline:

```sh
node apps/ios/Scripts/import-joviekit.mjs check \
  apps/ios/Vendor/JovieKit.source.json apps/ios/Vendor/JovieKit
python3 scripts/repository_docs.py
```

Updates belong in the canonical Jovie owner. Fetch a reviewed importer/manifest
revision, independently verify its hashes, import into a fresh review directory,
then update the package, receipt and source registry together. Use the same
importer's `import <manifest> <fresh-destination>` command. Do not hand-edit
vendor files. Reverting the consumer commit restores the prior import.

## Completion and presentation

`PhotoMetadataService.createOrUpdateMetricsWithResult` wraps awaited Core Data
persistence for a newly created manual measurement row in
`BodyRecordReviewConsumer.saveNewManualRecord`. Failed saves retain their errors.
Existing rows, same-day retries/corrections, onboarding baselines, explicitly
sourced imports and photo-only saves do not create opportunities. Completion
means local persistence, with cloud sync still pending. Measurement values,
method, direction and sentiment do not enter admission.

One installation-wide `@MainActor AppReview.Coordinator(load:save:)` considers
`.completedWorkflow` opportunities. Completion time is the save time, rather
than a historical measurement date. Native presentation rechecks the current
owner, actual hosting window, active foreground, modal/navigation transitions,
editing, gestures and scrolling after a settling interval. Root readiness also
excludes loading, onboarding, authentication, legal consent, biometric lock and
reminder presentations. VoiceOver being enabled does not itself disqualify users.

The default-off gate is `body_record_app_review_v1`, accessed through
`AppServicePorts`. No experiment is activated. Future experiment policies must
supply matching, stable assignments from their existing owner.

The StoreKit adapter reads only the verified app transaction's production
environment. Missing, unverified, sandbox and debug distributions fail closed;
it never refreshes the transaction or requests sign-in. Scene/interaction state
is sampled again after that asynchronous read. Invocation uses
`AppStore.requestReview(in:)`; Apple owns the UI and actual display.

Pending opportunities are in memory and scoped to their owner. A protected,
atomic installation ledger preserves fatigue across app/policy revisions.
Corrupt storage and failed reservations fail closed. A crash after reservation
can conservatively consume fatigue before invocation. Receipts stay on device;
no new analytics event or health-data transfer is added. `request_invoked` is
observable; display, dismissal and review submission remain unobservable.
[TestFlight requests have no effect](https://developer.apple.com/documentation/storekit/appstore/requestreview%28in%3A%29-1q8qs/).

Future API/MCP/Siri entry points reuse product-action completion plus an
authenticated native handoff. This integration adds no server review tool and
does not change Siri create/retry semantics.

## Verification boundaries

The actual LYB Xcode project resolved the relative package successfully with
`xcodebuild -resolvePackageDependencies -scmProvider system`; existing remote
package versions remained unchanged. This is resolution proof, not an app build.
The imported snapshot passed all 42 Swift package tests. Twelve consumer XCTest
cases passed against that snapshot, covering failed/awaited saves, duplicates,
restart/fatigue, offline/readiness, account isolation, persistence failures,
assignment and local receipt contents.

The existing shared-lib Vitest suite executes the real importer offline and
rejects policy, receipt and unexpected-file drift. Its Turbo inputs include
vendor source, importer and registry, so updates cannot reuse a stale integrity
result. Commit-hook Swift selection matches the existing SwiftLint app/test
scope; immutable vendor source is checked through provenance and its owner tests.
No product lint rule or required workflow is removed.

`BodyRecordReviewConsumerTests` is registered in `LogYourBodyTests` and included
by the real `LogYourBodyTiers` / `Unit` selector. Full app build, native Unit
execution/current whole-app coverage (including the 70% requirement), UIKit
invocation tests, rendered/device acceptance and rollout remain pending. Keep
the gate off until those checks pass. Do not infer prompt display or review
outcomes from policy fixtures or TestFlight.
