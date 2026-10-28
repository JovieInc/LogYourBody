# App Store privacy answers (LYB-194)

[`app-store-privacy.json`](app-store-privacy.json) is the versioned App Store
Connect (ASC) questionnaire for the native LogYourBody app. Each `dataTypes` row
is a **collected** data type and records Apple's data-type name, purposes, linkage,
tracking answer, processor use and source evidence. Top-level answers are **data
collected: Yes; data used for tracking: No**. These are source-reviewed answers,
not a receipt that the current ASC console or a submitted binary has been checked.
`ascComparison.status` is **pending** until Tim completes the comparison below.

Use Apple's [App privacy details](https://developer.apple.com/app-store/app-privacy-details/)
definitions when editing answers. Off-device retention by our service providers
counts as collection; optional HealthKit access, feature gates and an analytics
allowlist do not exempt collected data. Data processed only on device is excluded.
The answers cover supported optional collection paths, including configured
performance tracing and coach features, rather than assuming a gate stays off.

The five HealthKit read types are `bodyMass`, `bodyFatPercentage`, `height`,
`dateOfBirth` and `stepCount`. Only `bodyMass` and `bodyFatPercentage` are written.
`healthKit` maps each identifier to its ASC data type and read/write permissions.
`usageDescriptions` records every reviewed `NS*UsageDescription` in Info.plist;
permission text alone does not determine whether data is collected off device.
The [privacy policy](../../shared/legal/privacy-policy.md) describes account,
profile, health, photo and processor handling; review it with any collection change.

## Linkage and processor interpretation

- Health/profile records, photos, messages and purchases are linked through the
  account. Health data and photos are used for app functionality and the stated
  coach personalization, never advertising or data-broker use.
- Statsig receives allowlisted event markers and fixed enums, not app-supplied
  user IDs or health values. Its stable installation ID, automatic metadata and
  gate exposures still count. **Product Interaction and Device ID are linked**
  through that identifier. See the SDK's [StableID and metadata behavior](https://docs.statsig.com/client/iosClientSDK).
- Sentry automatic errors disable default PII and redact account/health fields.
  That does not prove all SDK diagnostics are unlinked. Crash, performance and
  diagnostic rows conservatively say **linked: Yes**. User-initiated
  `SentryFeedback` separately sends a name, email, message and optional screenshot;
  do not apply the automatic-error redactor's guarantee to feedback attachments.
- **Tracking: No** means no joining with other companies' data for targeted ads,
  advertising measurement or data-broker sharing. It does not mean “no analytics”
  or “no third-party processor.” Verify SDK/archive behavior and provider settings
  before claiming this answer is proven for a release.

## Data not selected in ASC

- Face ID biometric templates stay with the operating system; the app only gets
  an authentication result. Local photo-library scanning and saving a share image
  do not collect the whole library off device. Uploaded photos are disclosed.
- Native voice capture uses Apple Speech on device where available and may use
  Apple's network recognition otherwise. Our native voice API sends **text** to
  intent parsing and receives synthesized audio for playback; it does not upload
  microphone recordings. Audio Data is not selected for our own collection.
  Apple's framework collection is distinguished from developer collection by
  Apple's guidance. Revisit this answer if raw audio goes to our servers or a
  non-Apple transcription provider, or we retain recordings.
- Payment cards/bank details stay with Apple's payment service. Purchase History
  is disclosed separately. No ad identifier, location permission, contacts,
  browsing history or cross-app tracking is asserted by this inventory.

## PrivacyInfo is a separate artifact

[`PrivacyInfo.xcprivacy`](../../apps/ios/LogYourBody/Resources/PrivacyInfo.xcprivacy)
currently declares Required Reason APIs: UserDefaults (`CA92.1`), FileTimestamp
(`C617.1`) and SystemBootTime (`35F9.1`). These explain API access reasons and do
**not** answer ASC's collection, purpose, linkage or tracking questions. SDKs can
also supply manifests in the archive. See Apple's [privacy manifest documentation](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files).

Keep Required Reason API review and ASC nutrition-label review separate. Do not
invent `NSPrivacyCollectedDataTypes` entries merely to copy this questionnaire
into the target manifest. Add such entries only when Apple/tooling requirements
for this target call for them, with a separate review of the archived manifests.
This change leaves the target manifest and runtime collection unchanged.

## Drift gate and maintenance

The existing required **Detect Changes** correction-ratchet step runs
[`app-privacy.mjs`](../../packages/shared-lib/scripts/app-privacy.mjs) on **every
diff**, including iOS-only and docs-only changes. Its empty baseline rejects a
missing/incomplete questionnaire, changed HealthKit type definitions, read/write
sets, additional authorization owners, or any added/removed/changed Info.plist
usage description. It reads the supplied Git snapshot, without credentials or
ASC access. Refactoring the literal HealthKit declarations requires updating the
scanner, not bypassing it. Other data flows and provider settings still require
source and archive review; this scanner is not a whole-program privacy audit.

Run from the repository root:

```sh
node packages/shared-lib/scripts/correction-ratchet.mjs --base-ref origin/main
node --test packages/shared-lib/scripts/app-privacy.behavior.mjs
pnpm test --filter=@logyourbody/shared-lib
```

When collection changes, edit the questionnaire and relevant policy in the same
PR, increment `version`, update the review date/native source reference, reset
the ASC comparison to pending and include the changed rows in release evidence.
Do not auto-regenerate answers or just refresh permission snapshots to silence
the guard. Recheck SDK changes and the archive privacy report as part of that review.

## Tim's initial ASC comparison and release evidence

Before the first submission using this inventory, Tim opens ASC → LogYourBody →
App Privacy and compares **every collected data type**, every purpose, linkage
and tracking answer with the JSON. Correct differences in ASC (or correct the
versioned answers with source evidence). Record the date, questionnaire version,
source commit, TestFlight version/build, reviewer and a redacted ASC export or
screenshots in the release evidence. Only then mark `ascComparison` confirmed
with an evidence reference. The initial confirmation remains outstanding here;
agents must never manufacture it from a green source gate.

For later submissions, compare the release's questionnaire diff and archive SDK
privacy report with that receipt. Reconcile any changed answer in ASC before
submission. Keep the paywall purchase/restore attestation as well. This is a
release-evidence requirement, not a new workflow input or a claim that CI reads ASC.

Store only non-secret evidence references. No ASC API token, signing key,
account credential, access token, customer record or unredacted customer screenshot
belongs in this questionnaire or its release receipt.
