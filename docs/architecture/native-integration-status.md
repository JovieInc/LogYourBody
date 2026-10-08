# Native integration status

The native Settings → Integrations directory uses the shared integrations
semantics: availability, connection or permission state, and data history are
separate observations. The first native slice is behind the default-off Statsig
gate `lyb_integrations_directory_v1`, accessed through the analytics port.
Debug UI runs can enable it with `-lybUITestIntegrationsDirectoryFixture`.

Provider metadata lives in the existing product registry's
`src/products/logyourbody-integrations.mjs` and generates the native labels,
authorization modes, supported platforms, and operation labels. This extends
the current package and generator; it adds no provider runtime. The operation
shape matches the Jovie manifest semantics. Cross-repository code reuse still
requires the documented versioned package extraction, not copying or symlinks.
Declared scopes describe an operation's needs; they are not permission grants.
BodySpec is excluded from marketing until production configuration is verified.

Apple Health lists supported weight, body-fat, and step data. A completed
authorization request or write authorization does not prove permission to read
all of those samples. The directory describes the sync preference and offers
setup or permission-management guidance. Unavailable Mac HealthKit shows
“Use on iPhone”; no web OAuth, cross-device authorization, or automatic phone
handoff is implied. Sync completion copy describes the completed request, not
proof of a nonempty import.

BodySpec uses the existing native OAuth/API adapter and DEXA importer. The
directory reads build configuration and token validity independently of scan
history. Its saved connection is device-scoped in the current adapter; the
directory does not expose a saved email as the current LogYourBody user's
identity. Cross-account token ownership requires its own adapter repair before
claiming a user-scoped connection.

The latest scan is selected by acquisition date from BodySpec records only.
Record update time is not a scan date or a sync receipt. Missing scan dates stay
unknown. A failed history refresh preserves cached history and connection state
and provides a direct retry. Results from cancelled tasks or a different signed-in
user cannot update the directory or its cache.

This slice retains existing Settings routes, export, import, and mutation
services. It does not implement the LYB-80 MCP transport or certify the complete
LYB-81 ingestion/dedup workflow. The existing importer can report failures as
skips, so its counts are not sufficient evidence of complete sync success.

## Platform boundary

Current project source declares an iOS 26 iPhone/iPad app and no dedicated
macOS or Catalyst target. Apple's iPhone/iPad-on-Apple-silicon distribution is
the first candidate for reusing this screen on Mac. App Store Connect eligibility,
availability, and an actual Mac launch must be verified before claiming delivery.
No new Mac runtime is introduced by this change.

Primary references:

- [HealthKit availability](<https://developer.apple.com/documentation/healthkit/hkhealthstore/ishealthdataavailable()>)
- [HealthKit authorization status and read privacy](https://developer.apple.com/documentation/healthkit/hkauthorizationstatus)
- [iOS app availability on Apple silicon Macs](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/manage-availability-of-iphone-and-ipad-apps-on-macs-with-apple-silicon)

## Validation boundary

`HealthKitAuthorizationPolicyTests` exercises unsupported platform, request,
and sync-preference display states. `BodyMetricSourceContractTests` exercises
configuration/connection separation, BodySpec-only scan selection, unknown dates,
and account-switch/cancellation refusal. Both existing targets are discovered by
the CI unit-tier plan; no Xcode target or workflow edit is needed.

The registry's real `pnpm product:check`, scoped root lint/typecheck, strict
SwiftLint and Swift syntax parsing passed locally. Native test
execution, current runner coverage, rendered screen review, CI, merge, release,
and real permissions/connections remain separate required receipts.
