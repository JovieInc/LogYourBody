# Body-reconstruction provider and derived-asset consent (LYB-321)

Recorded: 2026-10-31. Parent: LYB-311.

## Decision

**Question:** May the LYB-311 program add a reconstruction provider, API credential,
or external upload such as Anny?

**Answer: No.** Apply the issue's authorized default; no override is recorded.
The program must not add a body-reconstruction provider, a new API credential,
or a new external photo upload, including Anny. Reusing an existing credential
does not authorize a new provider or upload destination.

## Derived-asset boundary

- Treat silhouettes, meshes, and rendered assets derived from a user's photos or
  health data as sensitive health artifacts. Transformation does not make them
  anonymous or expand consent.
- Keep derived assets within the existing user-authorized local storage and
  first-party account-scoped sync/storage paths. Use only already-authorized
  purposes and providers, subject to the existing provider consent. Do not add a
  storage service or an external upload of originals or derivatives.
- Preserve the source data's existing retention and deletion behavior for every
  derived asset and cached copy. Derived assets must participate in the same
  applicable photo/account deletion paths; they must not survive those deletions
  in a separate store.
- If the existing consent, storage, or deletion path cannot cover an operation,
  leave that operation unavailable. This decision does not implement or certify
  support for derived assets.
- Do not put original photos or derived health artifacts in public fixtures,
  tracker attachments, or telemetry, including logs and analytics. Review evidence
  for this slice is text and source references only.

## Existing paths and limits

The [privacy policy](../../shared/legal/privacy-policy.md) documents progress-photo
storage, consent-based sharing, and Settings > Delete Account. The existing
[legal consent screen](../../apps/ios/LogYourBody/Views/LegalConsentView.swift)
collects Terms and Privacy Policy acceptance, recorded by
[`AuthManager.acceptLegalConsent`](../../apps/ios/LogYourBody/Services/AuthManager.swift).
That acceptance, photo-library access, and HealthKit permission do not grant
permission for a new reconstruction provider or transfer.

Existing cloud photo storage uses the
[first-party photo API](../../apps/web/src/app/api/auth/mobile/photos/route.ts)
and [account-scoped R2 adapter](../../apps/web/src/lib/cloudflare/r2-progress-photo-store.ts).
The [mobile account deletion route](../../apps/web/src/app/api/auth/mobile/profile/route.ts)
invokes owned-photo cleanup before deleting the product account. These are source
references for the existing boundary, not new provider or credential approvals.

The privacy-visibility decision in the LYB-311 split remains a prerequisite for
downstream asset work; this record does not decide visibility or waive that
dependency. Evidence fusion stays with JOV-6014. Imports stay with LYB-80, LYB-81,
and LYB-171. Other LYB-311 work is outside this decision.

This slice changes documentation only: no native app code, secrets, package
manifests, provider configuration, or health artifacts are added or changed.

LYB-315 later stores versioned visualization snapshots and local derived
placeholders in the account's application-support directory. Authentic photos
may only reference the existing progress-photo prefix above. That work adds no
provider, credential, or upload. The interface is
[body visualization snapshots](../engineering/body-visualization-snapshots.md).
