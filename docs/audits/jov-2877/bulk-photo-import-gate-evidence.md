# JOV-2877 Bulk Progress-Photo Import Gate Evidence

## Scope

Bulk progress-photo import remains out of the default paid MVP path. The existing scanner entry is now shown only when either:

- the `ios_bulk_progress_photo_import` feature gate is enabled for a migration cohort, or
- the user has activation evidence from at least two existing progress photos.

No bulk import, photo scanner, billing, auth, or privacy behavior was expanded.

## Runtime Evidence

- Default paid-MVP fixture shows the Integrations photo import row as locked with migration-access copy.
  - `bulk-photo-import-locked.jpg`
- Enabled migration fixture shows the row as `Scan library`.
  - `bulk-photo-import-enabled.jpg`
- Tapping the enabled row opens the existing `Bulk Photo Import` scanner landing screen with `Start Scanning`.
  - `bulk-photo-import-scanner.jpg`

## Validation

Simulator: `iPhone 17 Pro`, `1F5679FD-2B72-40E4-816A-4B58E36C032B`

Commands run:

```bash
swiftlint lint --strict
xcodebuild -project LogYourBody.xcodeproj -scheme LogYourBody -destination 'platform=iOS Simulator,id=1F5679FD-2B72-40E4-816A-4B58E36C032B' -only-testing:LogYourBodyTests/BulkProgressPhotoImportPolicyTests test
xcodebuild -project LogYourBody.xcodeproj -scheme LogYourBody -destination 'platform=iOS Simulator,id=1F5679FD-2B72-40E4-816A-4B58E36C032B' -only-testing:LogYourBodyUITests/LogYourBodyUITests/testBulkPhotoImportLockedByDefaultInIntegrations -only-testing:LogYourBodyUITests/LogYourBodyUITests/testBulkPhotoImportGateOpensScannerEntry test
xcodebuild -project LogYourBody.xcodeproj -scheme LogYourBody -destination 'platform=iOS Simulator,id=1F5679FD-2B72-40E4-816A-4B58E36C032B' build-for-testing
pnpm lint
pnpm typecheck
pnpm test
git diff --check
```

Results:

- SwiftLint: passed, 0 violations.
- Bulk import policy tests: passed.
- Bulk import UI smoke tests: passed.
- iOS build-for-testing: passed.
- Root `pnpm lint`, `pnpm typecheck`, and `pnpm test`: passed. Existing repo warnings were limited to Node 22 vs expected Node 20, cached Next/build warnings, and existing test console output.
- `git diff --check`: passed.

## Done When

JOV-2877 is done when the default paid MVP path does not expose bulk photo import, a migration or activation cohort can still open the existing scanner, and automated plus screenshot evidence covers both states.
