# LYB launch readiness — October 26, 2026

**Decision: not yet launch certified.** This audit started from
`40224a09e227af6db41fa2ff60cc8487c8778997` and implements the reviewed changes on
`agent/lyb-launch-readiness`. Source evidence and local execution do not establish
App Store availability, device quality, live conversion, or provider commissioning.

## Implemented

- Purchase results require active entitlement and honor SDK cancellation behind
  `billing_verified_purchase_outcome_v1`. The policy is captured once per attempt;
  existing account/session ownership checks remain in force. Eight native cases
  cover the new behavior, including restore recovery and an in-flight gate change.
  The gate remains off until native qualification and controlled rollout.
- Optional Statsig SDK failures cannot interrupt signup or prevent the Vercel
  adapter from running. Both existing waitlist forms emit bounded attribution on
  start, attempt and outcome. Duplicate acceptance remains indistinguishable.
- The existing private growth report supplies source-repair actions and cohort
  maturity dates. It does not infer customers, revenue or experiment winners from
  client events. See the [funnel contract](../marketing/funnel-evidence-contract.md).
- Generated App Store copy explains benefits, units, eligible trials, renewals,
  cancellation and legal links. The search field includes weight intent. Published
  articles enter the sitemap and have article-specific share metadata; draft posts
  remain excluded. Unused misleading marketing copy was removed.
- Fourteen deliberate JavaScript mutants exercise growth qualification and release
  provenance. The required suite rejects survivors, errors, stale anchors, empty
  source coverage and incomplete runs. Independent review reproduced and fixed
  zero-execution coverage and orphaned timeout processes.
- The existing web suite now collects coverage and enforces measured global floors
  without excluding retained source. Browser/server ports are aligned, prelaunch
  fixtures have deterministic flags, and a fresh server prevents accidental reuse
  of an incompatible rollout. The focused browser suite covers six public pages,
  canonical URLs, keyboard activation and signup recovery.

## Evidence and limits

| Area                 | Executed evidence                                                                                                             | Limit                                                                                                |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| Web behavior         | 141 suites, 1,409 tests passed in the full measured coverage run                                                              | Authenticated providers and production persistence were not commissioned                             |
| Whole-web coverage   | 54.43% statements, 56.11% branches, 56.74% functions, 55.92% lines                                                            | Baseline, not full coverage; normal test/CI commands now enforce nonregression                       |
| Mutation campaign    | 14/14 curated faults detected; growth source 100% line/branch/function; selected release policy 81.32%/98.70%/100%            | Two JavaScript modules, not Swift or whole-app mutation coverage                                     |
| Mutation runner      | 8 tests; 99.38% lines, 98.39% branches, 100% functions                                                                        | Includes real empty-coverage and timeout regressions                                                 |
| Browser              | All 18 desktop/mobile Chromium cases passed with deterministic prelaunch flags and normalized canonical URL checks            | Signup acceptance/error responses are intercepted; no durable registration or live analytics receipt |
| Native static checks | UI regression, vendor boundaries, performance-smell audit passed; optical audit has three retained findings, zero regressions | These do not run Swift or prove device performance/accessibility                                     |
| Native coverage      | Retained quality-unit floor 26,397/103,629; unit-tier floor 21,069/103,629                                                    | Historical independent selectors, approximately 25.47% and 20.33%; no new XCTest result here         |

Regression failures were demonstrated before the analytics, funnel, report and
SEO fixes. Native behavior tests could not execute because this Linux environment
has no Swift/Xcode. Full repository validation also initially found missing Ruby
and an outdated retained sitemap guard anchor; the local Ruby runtime and source
anchor were repaired without weakening checks. Final root `pnpm lint`,
`pnpm typecheck` and `pnpm test` passed. The full test command completed all eight
tasks, including 181 shared-lib cases, 122 workflow script cases and the 1,409 web
cases. The production web build also completed. Some unchanged tasks reused Turbo
cache; `pnpm test:mutation` was run separately without cache and again killed all
14 faults. These receipts qualify the source working tree; hosted checks must
still verify the PR commit.

## Remaining release gates, in order

1. **Candidate code qualification.** Run the existing native Unit and Launch
   Quality gates on the final commit, including the purchase cases. Retain named
   failures/skips, xcresults, same-selector coverage and installed-build identity.
   Native billing rollout remains off until this succeeds.
2. **Signing and Apple account readiness.** The coordinator reported a missing
   rest-timer App Store provisioning profile in run `40400354908`; this session
   did not verify a repair. Preserve the extension and readonly signing policy.
   Apple agreement acceptance is independently unknown. Do not create credentials
   or accept agreements as a test workaround.
3. **Device acceptance.** Obtain current-build cold-launch, frame-time and hitch
   traces on a declared device, plus VoiceOver, large text, reduced motion,
   offline/retry, HealthKit import, sync/delete/export and authentication evidence.
   Current CI performance steps are static-only; total XCTest duration is not
   time to usable UI. Run the existing performance and ETTrace workflows.
4. **Storefront production.** Capture seven real, synthetic-data app states and
   compose the approved direction from the [production brief](../marketing/app-store/launch-production-2026-10-26.md).
   The retained iPhone image contains an offline banner and clipped content. It
   does not satisfy the campaign. No screenshots, store metadata or agreements
   were published by this work.
5. **Commerce and privacy receipts.** Follow [the existing release runbook](../RELEASE_APP_STORE.md).
   Its initial ASC privacy comparison is pending. Authorized real-device
   TestFlight purchase/restore, current offering/product readback and archive SDK
   privacy evidence are still required. No live purchases or manual deployments
   are performed in this work. A green ASC readback job can still contain FAIL
   rows; inspect the result table.
6. **Commissioned funnel.** Verify production event delivery, exclusions and
   receipt provenance across acquisition, activation, retention and ledger-backed
   money. Coaching-benefit qualification remains owner-defined and unknown. Do
   not enable growth gates or report conversion from source implementation alone.

## Iteration and custody

Use `pnpm growth:report` with bounded, private aggregate receipts and act on its
repair actions before evaluating an experiment. Keep one hypothesis, one primary
metric, guardrails, a maturity window and an explicit decision receipt. The
existing Summer capability can consume this stable report contract when its
owner commissions the sources; this change creates no parallel monitor,
scheduler, provider connection or autonomous campaign writer.

The existing LYB merge-queue repair cohort retains its incumbent PRs. This branch
does not rewrite, merge or deploy them. Store publication and account-owner
attestations remain separate from normal source review. GBrain is unavailable in
this environment, so durable external writeback/readback is unverified; this
committed audit is the local handoff record.

Useful commands (repository root):

```bash
pnpm lint
pnpm typecheck
pnpm test
pnpm test:mutation
pnpm test:launch-e2e
pnpm product:check
pnpm ios:launch-quality-audit   # macOS/Xcode
pnpm ios:performance-audit      # macOS/Xcode
```

On this Linux host, activate `/workspace/.cloud-setup/activate.sh logyourbody`.
Browser checks can use `PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH=/usr/bin/chromium`.
Keep raw test outputs and aggregate analytics in controlled operator storage;
do not publish account or health data in artifacts.
