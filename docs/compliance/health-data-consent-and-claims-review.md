# LYB-328 health-data consent and claims review

Reviewed: 2026-11-01. Issue: [LYB-328](https://linear.app/jovie/issue/LYB-328).
Source snapshot: `3f3f05bcdb19b354ed178ddd7d0e3cdfa3de853c`.
Disposition: **source review complete; coached-tier launch not cleared**.
Counsel sign-off: **pending**. No legal approval or live release verification is
recorded here. The issue's LYB-1 link is a timeline bug reference, not consent or
legal evidence. GBrain was unavailable; findings below use repository sources.

## Consent findings

| Surface                           | Source evidence                                                                                                                                                                                                                                                                                                                                                                                                         | Review result and required closure                                                                                                                                                                                                                                                                                                                                                                 |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| General onboarding                | [LegalConsentView](../../apps/ios/LogYourBody/Views/LegalConsentView.swift) starts Terms and Privacy acceptance unchecked. [Mobile profile API](../../apps/web/src/app/api/auth/mobile/profile/route.ts) records legal acceptance and document versions.                                                                                                                                                                | General document acceptance exists. It does not establish separate, purpose-specific consent for photo collection, analysis, DEXA transfer or coaching. Do not count a legal-acceptance timestamp as a feature consent receipt.                                                                                                                                                                    |
| Single progress photo             | [ProgressPhotoAttachSheet](../../apps/ios/LogYourBody/Views/ProgressPhotoAttachSheet.swift) previews library selections and offers Attach Photo. Its camera completion calls `attachSelectedPhoto()` automatically. [PhotoUploadManager](../../apps/ios/LogYourBody/Services/PhotoUploadManager.swift) implements storage/upload.                                                                                       | **Explicit health-data consent not verified.** Camera permission and selection do not explain account storage, sync, recipients or withdrawal. Require an informed affirmative choice before collection/upload; camera capture must not silently stand in for that choice. Cover onboarding, camera, library and replacement paths.                                                                |
| Bulk progress photos              | [BulkPhotoImportView](../../apps/ios/LogYourBody/Views/BulkPhotoImportView.swift) explains on-device scanning, says only selected photos upload, and asks for import confirmation.                                                                                                                                                                                                                                      | Selection and confirmation safeguards exist. The dialog does not establish a versioned health-data consent receipt or withdrawal flow. Review scan access separately from cloud upload and any later analysis. Keep the existing bulk-import gate off pending evidence.                                                                                                                            |
| DEXA/InBody PDF import            | [DexaPDFImportSheet](../../apps/ios/LogYourBody/Views/DexaPDFImportSheet.swift) invokes `readReport()` in `.task`. [DexaPDFImportCoordinator.parse](../../apps/ios/LogYourBody/Services/BodySpecDexaImporter.swift) uploads the PDF to `/api/parse-pdf`; that [route](../../apps/web/src/app/api/parse-pdf/route.ts) sends extracted report text to OpenAI through the completion port. Add to timeline runs afterward. | **Explicit consent before transfer is missing in this path.** Selecting a file or later saving extracted values is not evidence of informed consent to the parser transfer. Disclose report data, extraction purpose, provider categories, storage and withdrawal before any upload. Cancellation must make no parser request. The original-PDF-not-saved message does not disclose this transfer. |
| Optional BodySpec account sync    | [BodySpecIntegrationView](../../apps/ios/LogYourBody/Views/BodySpecIntegrationView.swift) offers Connect, Sync and Disconnect when configured. [BodySpecAuthManager](../../apps/ios/LogYourBody/Services/BodySpecAuthManager.swift) requests OAuth scopes; [BodySpecDexaImporter](../../apps/ios/LogYourBody/Services/BodySpecDexaImporter.swift) fetches results and writes account-owned records for sync.            | Provider authorization and disconnect controls exist. The hosted authorization notice, production configuration and purpose-specific consent/withdrawal receipt were not verified. Review direct-provider import separately from PDF parsing; a parser fix alone cannot clear all DEXA collection.                                                                                                 |
| Alternate PDF parser              | [/api/parse-pdf-v2](../../apps/web/src/app/api/parse-pdf-v2/route.ts) also sends extracted text to the completion port; its handler has no authentication or consent check.                                                                                                                                                                                                                                             | Treat this as an unresolved parallel ingress during remediation. Removing access from one native screen would not establish that every parser ingress is protected. Engineering must retire or protect the route and test unauthorized and unconsented requests before clearing import.                                                                                                            |
| Photo analysis and derived assets | [First-photo onboarding](../../apps/ios/LogYourBody/Features/Onboarding/Views/BodyScoreFirstProgressPhotoView.swift) says analysis requires consent. [LYB-321](../architecture/body-reconstruction-consent.md) forbids a new reconstruction provider or external upload and treats derivatives as sensitive health artifacts.                                                                                           | An analysis promise is not an implemented consent receipt. Preserve the LYB-321 boundary; ordinary photo-storage permission must not authorize analysis, a new provider, or a new purpose.                                                                                                                                                                                                         |

Engineering owns consent enforcement and regression evidence; Tim/product owns
purpose and recipient inventory; counsel must approve the legal basis and final
notice. For each optional purpose, retain the account subject, purpose/data
scope, notice version, affirmative action/time, and withdrawal state. Declining
must leave unrelated features usable. Enforce authorization at the service/API
boundary as well as the screen, including background work, retries, account
changes and consent revocation. These are acceptance requirements, not claims
that such controls already exist.

## Policy and jurisdiction review

The canonical [consumer-health-data policy](../../shared/legal/consumer-health-data-policy.md)
exists at the distinct [/consumer-health-data route](../../apps/web/src/app/consumer-health-data/page.tsx).
The [publication regression](../../apps/web/src/app/__tests__/consumer-health-policy.test.tsx)
covers its required sections and visible links in five homepage/footer surfaces.
This is source publication evidence; deployed content was not read back.
The broader [App Privacy inventory](app-store-privacy.json) also lists imported
results, medication logs and training pain/safety feedback. Reconcile those
categories with the public policy for each enabled surface; the current policy
list is not a complete inventory of the repository's possible health data.

| Area                             | Finding                                                                                                                                                                                                                                                                                                              | Required before launch clearance                                                                                                                                                                                                                                                                                                                                                                            |
| -------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Washington MHMDA                 | The policy lists measurements, HealthKit, profile details, photos and chat; it omits DEXA reports/extracted text and the parser provider transfer. Its withdrawal examples are Health app revocation or account deletion.                                                                                            | Reconcile all collected/inferred categories, purposes, sources, recipient categories and specific affiliates with actual data flows. Provide a workable withdrawal route for optional collection/sharing without requiring account deletion. Verify access, deletion propagation, appeal handling and policy publication.                                                                                   |
| California sensitive information | [CCPA notice](../../shared/legal/ccpa-compliance.md) identifies health information, but generically labels photos biometric information and points to unspecified settings for limiting use. It also contains example annual metrics and unverified retention/security statements.                                   | Counsel must assess applicability and whether uses remain within permitted requested-service purposes or trigger the right to limit. Engineering/product must demonstrate the actual request path and purpose limits. Reconcile photo classification with actual processing; do not assume every photo is a biometric identifier. Replace unsupported public assertions only through reviewed policy edits. |
| GDPR                             | [GDPR notice](../../shared/legal/gdpr-compliance.md) says explicit health-data consent is obtained during onboarding, but the onboarding source above shows only document acceptance. It asserts end-to-end encryption, signed transfer safeguards and retention periods without supporting receipts in this review. | Counsel must document the Article 6 basis and Article 9 condition per purpose, consent/withdrawal evidence, controller/processors, transfer mechanism and whether a DPIA or representative is required. Verify encryption, processor contracts, deletion/backup periods, exports and age handling against production before retaining those claims.                                                         |

These are review findings, not a determination that a particular law applies or
that a statutory exception is available. Official sources checked 2026-11-01:

- [Washington RCW 19.373](https://app.leg.wa.gov/RCW/default.aspx?cite=19.373&full=true),
  especially .010, .020, .030 and .040: specific informed opt-in, a distinct
  policy, consumer rights and separate sharing consent where required. Section
  .030 also has a requested-service necessity exception; counsel must assess
  its application rather than assume all processing requires the same consent.
- [California Privacy Protection Agency FAQ](https://www.cppa.ca.gov/faq.html):
  health information is sensitive, the right to limit depends on use, and CCPA
  coverage has applicability thresholds. A no-sale statement does not establish
  that all sensitive-data duties are satisfied.
- [GDPR, Regulation (EU) 2016/679](https://eur-lex.europa.eu/eli/reg/2016/679/oj/)
  and [European Commission guidance](https://europa.eu/youreurope/business/governance-and-sustainability/digital-and-data-compliance/data-protection-gdpr/index_en.htm):
  health data has special protection; explicit consent is one possible exception.
  The EUR-Lex full-text fetch was challenge-blocked; the Commission guidance was
  available. Counsel must verify Articles 6, 7 and 9 against the authoritative text.

## Claims and medication review

The [Terms](../../shared/legal/terms-of-service.md),
[Health Disclosure](../../shared/legal/health-disclosure.md) and
[claims policy](claims-policy.md) position LYB as fitness/wellness information
and state that it does not provide medical advice. The claims policy separates
measurements, estimates, references and user targets; it rejects clinical and
guaranteed-outcome claims. This positioning must match functionality and the
complete impression of marketing and coach responses.

Medication advice is prohibited, but **absence from shipped behavior is not
verified**:

- The external agent's [always-loaded instructions](../../agent/instructions/compliance-guardrails.md)
  prohibit medication decisions and amounts and redirect concerns to a qualified
  healthcare professional. Its [definition](../../agent/agent.ts) includes a smoke
  assertion for those instructions. That runtime does not certify the separate
  native mobile chat API.
- The mobile chat [handler](../../apps/web/src/app/api/auth/mobile/chat/v1/route-handlers.ts)
  applies the [clinical output filter](../../apps/web/src/lib/chat/coach-scaffold.ts)
  only when [LYB_COACH_PERSONA_GUARDRAILS_V1](../../apps/web/src/lib/flags/coach-persona.ts)
  is `1`; unset defaults off. The general [system prompt](../../apps/web/src/lib/chat/context.ts)
  prohibits medical treatment, but the explicit medication prohibition is in
  the gated persona appendix. Instructions and regex fixtures cannot prove
  that live model responses never give medication advice.
- Native medication logging exists. [Glp1DoseDraftResolver](../../apps/ios/LogYourBody/Models/Glp1Medication.swift)
  uses a compatible previously logged amount or leaves the field empty; it does
  not generate a starting dose or titration. Preserve tracking-only scope and
  the GLP-1 quarantine. Do not describe logging as a medication recommendation.
- [Knowledge/claims lint](../../scripts/lint-claims.mjs) checks installed knowledge,
  agent instructions, evaluation output, storefront and web/legal copy. The
  [web claims handoff](web-claims-owner-handoff.md) retains legacy warnings for
  the copy owner. A passing scan is not a clean bill for every reachable native
  string or runtime response.

Engineering must show that clinical safety holds for the production mobile chat
path, including the default flag state, streamed text before display, stored
responses/replay, voice output and alternate agent path. Exercise requests to
start/stop a drug, change a dose, titrate, interpret medication effects or bypass
the restriction. Expected behavior is a bounded refusal and clinician referral,
with no new amount or treatment direction. Do not clear this item from prompt
text or a green static scan alone.

## Coached-tier release hold and evidence

The release owner must keep the coached tier unavailable to customers until all
items below have dated receipts. This document adds a release checklist hold;
it does not change production flags or install an automated launch gate.

- [ ] Tim/product and counsel approve the final consent purposes, notices,
      sensitive-data use, processor/transfer inventory and wellness claims for the
      exact coached-tier scope. Record reviewer, date, source revision, notice
      versions, approved scope and restrictions; reference restricted legal evidence
      without committing privileged advice or customer health data.
- [ ] Engineering closes the consent and parser-ingress findings above, with
      failing-then-passing tests and exact-build native evidence for accept, decline,
      cancel, withdraw, retry, account switch and deletion. No request or background
      transfer may precede required consent or continue after withdrawal.
- [ ] Tim/legal reconciles the consumer-health, privacy, CCPA and GDPR notices
      with actual behavior, including DEXA and chat processors. Verify the deployed
      policy and bundled copies, rights-request handling and production retention.
      The [LYB-189 prose review](healthkit-privacy-review.md) and
      [App Privacy comparison](app-store-privacy.md) remain separate prerequisites.
- [ ] Engineering/release owner supplies medication-refusal and claims evidence
      for every customer-reachable chat path, exact release build/configuration and
      current provider. Counsel approves coached-tier positioning before activation.

Review artifact delivery does not close those release items. This change adds
review documentation and citation registrations in the existing product registry;
it does not publish new legal promises or change consent, safety filters or rollout.
No native build, provider configuration, counsel opinion, deployed policy or
production conversation was verified on this Linux host.

## Local verification

Node `22.23.2` and pinned pnpm `10.34.1` were used. A temporary PATH wrapper made
nested pnpm calls use Corepack rather than the host's older global pnpm. The
product-registry fixture suite initially could not spawn Git in the sandbox
(`EPERM`); it passed with subprocess access through the normal approval reviewer.

Passed commands:

```bash
pnpm lint
pnpm typecheck
pnpm test
pnpm lint:knowledge
pnpm test:knowledge-lint
pnpm product:check
pnpm --filter logyourbody test:coverage --runInBand --coverage=false --runTestsByPath \
  src/app/__tests__/consumer-health-policy.test.tsx \
  src/lib/__tests__/load-legal-docs.node.test.ts \
  src/lib/chat/coach-scaffold.test.ts \
  src/lib/chat/context.test.ts \
  src/app/api/auth/mobile/chat/v1/__tests__/route.node.test.ts
python3 scripts/repository_docs.py
git diff --check
```

The focused run passed 47 tests in five suites; its scope intentionally omits
whole-app coverage collection and does not replace the full root test gate.
The final root test run passed all eight Turbo tasks (four cached), including
175 web suites / 1,693 tests. Claims lint retained existing copy-owner warnings.
The URL guard failed on the five new citation URLs before their registration
and passed afterward; legal-copy parity passed for all seven documents. No
product behavior was changed, so no new consent/runtime regression is claimed.

GBrain write to `logyourbody/lyb-328-health-data-consent-review` and readback of
that same slug both failed with connection refused at `127.0.0.1:7801`.
The committed review is the durable handoff; brain persistence is unverified.
