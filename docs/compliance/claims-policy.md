# Health and fitness claims policy

Reviewed 2026-09-27. This policy applies to LogYourBody's US consumer wellness and exercise coaching surfaces. It is a product communication standard, not legal advice or a regulatory classification.

## Recurring source review

Mission: keep primary-source guidance and product claims aligned.
Audience: Tim White and delegated compliance reviewers.

**Owner:** Tim White, accountable for completion and any legal/clinical review
needed. **Interval:** quarterly, on March 27, June 27, September 27, and December 27. **Next review due:** 2026-12-27, tracked by the assigned low-priority
[LYB-356 review checklist](https://linear.app/jovie/issue/LYB-356), established by
[LYB-191](https://linear.app/jovie/issue/LYB-191). Review sooner when a primary
source changes or product claims, medication scope, or health-data use changes.

The [quarterly calendar reminder](claims-policy-review.ics) repeats every three
months with a seven-day display alert. Import it once into the owner's calendar
to receive calendar notifications; import and notification delivery are not
verified here. The live Linear checklist is assigned and dated. Before closing
each review, create and link its successor with the same checklist, owner, low
priority, and next quarterly due date, then update the next-review date and issue
link above. Linear recurrence is carried forward by that checklist; native
automatic scheduling is not configured. A late review does not reset the cadence.

This is low-priority compliance hygiene. An overdue reminder or review alone
does not block App Store submission. A concrete compliance defect found during
review retains its own release controls, including the separate
[GLP-1 quarantine/clearance issue, LYB-190](https://linear.app/jovie/issue/LYB-190).

For every review:

- [ ] Retrieve every document in **Primary sources** from its official URL in the
      private compliance source register. Compare current text with the previous
      retained snapshot, including replacement/superseding guidance and changed
      section numbering. Cover Apple App Review 1.4.1 / 5.1.1 / 5.1.3 and the
      cited HealthKit guidance; FDA General Wellness, CDS, and SaMD; FTC health
      claims and endorsement guides.
- [ ] Record retrieval date, source version/issue date, previous and current
      snapshots, changed sections or an explicit no-change result, reviewer, and
      impact decision in the private register. If a source or prior snapshot is
      unavailable, record the gap and follow-up; do not mark it reviewed.
- [ ] Confirm quarantine/clearance in LYB-190 matches the current shipped product,
      feature-gate defaults and rollout state, coach instructions, and claims.
      Check native GLP-1 logging/check-in separately from coach material against
      the [product scope](../product/icp.md). Link the written clearance receipt
      or record the unresolved mismatch in LYB-190. A shipped logging feature,
      closed issue, or completed calendar event does not itself establish clearance.
- [ ] Update affected policy, corpus, guardrails, and evals, or link an owned
      follow-up with its release impact. Retain a receipt in the review issue
      with review date, reviewer, product commit/build, source diff/register
      references, GLP-1 status, and follow-up links. Keep private register contents
      out of the public repository.
- [ ] Advance each source's **Reviewed** date only after its comparison and impact
      assessment are complete; advance the policy's top-level **Reviewed** date
      only after the full review. Adding a cadence or reminder is not a source
      review. Create and link the next quarterly review before closing this one,
      and update the next-review date and reminder link above.

## Product purpose and claims

The coach supports general body-composition understanding and exercise training. It does not provide medical services or make claims about diagnosing, treating, curing, preventing, or managing a disease or health condition. Keep measured values, estimates, population references, and user-selected goals distinct. Explain the method and uncertainty of consumer measurements; do not imply clinical accuracy without validation for that exact use.

The deterministic training engine owns every set, rep, load, schedule, and adjustment. The conversation model may explain only engine-returned output and cite only the opaque evidence IDs supplied with it. It must not create, calculate, or alter numeric prescriptions. Do not promise a particular health, appearance, weight, or performance result, and do not claim FDA approval, clearance, exemption, or status without a product-specific determination.

Do not provide prescriptive aesthetic coaching to minors, pregnant or postpartum users, people with eating-disorder risk, or people pursuing unsafe targets. Do not assign appearance goals from immutable traits or infer preferences from sex or gender.

## Health data and HealthKit

Request only the health-data types needed for a feature, when the person needs that feature. Explain the purpose in plain language and respect the permission choices they make in system settings. Missing samples do not establish that a measurement does not exist. Keep the privacy policy current on collection, use, sharing, retention, deletion, and consent withdrawal.

HealthKit data must not be used for advertising, marketing, unrelated profiling, or resale. Do not share health data with a third party unless the purpose, disclosures, and permission meet current platform requirements. A permission prompt does not make a prohibited use acceptable.

## Evidence, advertising, and endorsements

Assess the complete impression created by text, images, omissions, and context. Substantiate objective health or safety claims before use with competent and reliable scientific evidence relevant to the exact claim, population, and outcome. A disclaimer cannot repair a contradictory main claim, and vague qualifiers do not reduce a misleading overall impression.

Endorsements must reflect the endorser's honest experience. Disclose material connections when the audience would not reasonably expect them. Do not present an atypical result without a clear and accurate account of the generally expected result. An endorsement cannot communicate a claim that would be misleading if the company made it directly.

## FDA scope

FDA's current General Wellness guidance covers qualifying low-risk products with a general-wellness intended use; examples include fitness, strength, weight management, muscle size, and body tone. Intended use depends on claims, labeling, interface, and functionality together. The coach does not rely on the healthcare-professional pathway for non-device clinical decision support and does not make disease-management or clinical-decision claims. A disclaimer alone does not establish a product's regulatory status.

## Medication and escalation boundaries

Medication decisions, amounts, and titration are outside the coach's scope. GLP-1 material remains quarantined unless the separate clearance checklist is completed and documented. Symptoms, injury, severe distress, or medication concerns should be redirected to a qualified healthcare professional. For immediate danger or urgent symptoms, direct the person to local emergency services.

Approved escalation language:

> Please contact a qualified healthcare professional for advice about your situation. I can help with general exercise information.

> Please contact local emergency services now.

## Automated claims gate

`pnpm lint:knowledge` scans every installed `agent/skills/` artifact, the always-loaded compliance instructions, and assistant-response fields in evaluation transcripts. It also scans text and Markdown files recursively under `apps/ios/fastlane/metadata/`, every string field in `apps/ios/fastlane/storefront-manifest.generated.json`, and the resolved `logYourBodyStorefront` definition in `packages/product-registry/src/storefronts/logyourbody.mjs`, including descriptions, subtitles, promotional text, and screenshot copy. Structured storefront fields are decoded and checked independently so a disclaimer in one field cannot suppress a claim in another. `pnpm test:knowledge-lint` exercises both the privacy and claims scanners, including prohibited storefront claims and allowed disclaimers. The claims scanner rejects positive clinical-action and disease assertions, medication direction and amounts, titration language, guaranteed outcomes, and unsupported FDA-status claims. It ignores user prompts because they are not assistant output. Static lint is a guardrail, not a substitute for evidence review or qualified legal and clinical review.

The same blocking CI command scans source text under `apps/web/src/app/`,
`apps/web/src/components/`, and `apps/web/src/constants/`, including copy modules,
JSX, page/layout metadata, and JSON-LD. It also scans the canonical product
registry, the shared privacy/terms/health Markdown and legal-loader fallback
copy, and published blog Markdown. API handlers, test/fixture/example files,
build outputs, and blog posts marked `draft: true` are excluded. Web rules also
flag trial offers, genetic-potential claims, and quantified weight/appearance
outcomes removed by the 2026-10-14 marketing audit. Qualified reference pricing,
trial eligibility language, and negated legal disclaimers remain allowed.

Existing web findings are recorded in
[`web-claims-baseline.json`](../../scripts/knowledge/web-claims-baseline.json)
and warn with a [copy-owner handoff](web-claims-owner-handoff.md). This baseline
is limited to the exact source statements and occurrence counts present at the
Git base. The required correction ratchet rejects baseline growth on every CI
diff; new or changed claims fail `pnpm lint:knowledge` immediately. Remove
resolved findings in the same copy-owner change. Do not rewrite flagged copy as
part of lint maintenance. Fixtures cover removed claims in copy, metadata and
JSON-LD, permitted disclaimers, and duplicate/changed baseline violations.

## Primary sources

- Apple App Review Guidelines, sections 1.4.1, 5.1.1, and 5.1.3; Apple Human Interface Guidelines, HealthKit; Apple Developer documentation on protecting HealthKit user privacy and authorizing access to health data. Reviewed 2026-09-27.
- FDA General Wellness: Policy for Low Risk Devices, issued 2026-01-06; Clinical Decision Support Software final guidance, January 2026; Software as a Medical Device overview. Reviewed 2026-09-27.
- FTC Health Products Compliance Guidance, issued 2022-12; Guides Concerning the Use of Endorsements and Testimonials in Advertising, published 2023-07-26. Reviewed 2026-09-27.

The private compliance source register stores the official first-party URLs and review dates for each cited document.
