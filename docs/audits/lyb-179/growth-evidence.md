# LYB-179 implementation evidence — October 16, 2026

Branch: `codex/lyb-179-20261016t070517`, based on
`9ffab8a4786e51d1b20f4695ef35df6324fd10d4`. The commit containing this file is
the source handoff; this document does not assert a deployed or installed build.

## Delivered source

- Existing first-run reveal emits a property-free `first_insight_rendered`
  occurrence through the sanitizing analytics port, after completed reveal,
  viewport visibility and foreground checks, once per in-memory flow. The new
  Statsig gate defaults off. No provider configuration was performed.
- `pnpm --silent growth:report <local-file.json>` composes strict private
  aggregate snapshots. It rejects sensitive/unknown fields, malformed windows,
  invalid/mismatched denominators, sandbox input, duplicate keys/sources/receipts
  and oversized/nonregular files. Unknown, stale, unreconciled, uncommissioned,
  incomplete and immature observations withhold qualified values.
- Canonical docs carry dated LYB-173 supersession while retaining v1 history.
  Pro references remain $9.99 monthly / $69.99 annual USD and three-day trial;
  older proposed premium packages are not treated as live offers.
- Five first-party reference teardowns and three exact private demo scripts are
  in [the preparation packet](../../marketing/growth-reference-demos-2026-10-16.md).
  Documentation URL registrations and their generated endpoint projection add
  no runtime integration.

## Executed local evidence

Node 22.23.2, pnpm 10.34.1, Linux. Commands ran from the repository root unless
specified. Local worker tests required the normal sandbox escalation because
the sandbox denies subprocess creation; no check was weakened or skipped.

| Command                                                                                                                                                                                                                                                    | Result                                                                                                                                                                                                  |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pnpm lint`                                                                                                                                                                                                                                                | Passed, four tasks                                                                                                                                                                                      |
| `pnpm typecheck`                                                                                                                                                                                                                                           | Passed, four tasks                                                                                                                                                                                      |
| `pnpm product:generate` / `pnpm product:check`                                                                                                                                                                                                             | Passed; generated projections, URL drift, legal parity and registry checks                                                                                                                              |
| `node --test --experimental-test-coverage --test-coverage-include=packages/shared-lib/scripts/growth-report.mjs --test-coverage-lines=90 --test-coverage-branches=85 --test-coverage-functions=100 packages/shared-lib/scripts/growth-report.behavior.mjs` | 11 behavior cases passed; report line/branch/function coverage each 100%                                                                                                                                |
| `pnpm --silent growth:report docs/marketing/growth-evidence.empty.json`                                                                                                                                                                                    | Passed; all eight metric values null/unknown, no fabricated production receipts or outcomes                                                                                                             |
| Scoped `swiftlint lint --strict --no-cache --config apps/ios/.swiftlint.yml` on the four changed Swift files                                                                                                                                               | Zero violations; SourceKit-dependent rules unavailable on this Linux host. The first cached attempt failed writing `/var/tmp`; the normal no-cache invocation passed.                                   |
| `pnpm test`                                                                                                                                                                                                                                                | Two normal parallel runs: web 1,026 passed / one five-second timeout in unchanged `MesocycleCanvasBoard.test.tsx`; the second run canceled the still-running shared-lib task. No test or limit changed. |
| `pnpm --filter logyourbody test:ci`                                                                                                                                                                                                                        | Passed the existing serial CI entrypoint: 118 suites / 1,027 cases, plus three voice-adapter cases. The parallel root-command timing failure remains a host/CI concern; it is not claimed green.        |
| `xcodebuild ... build-for-testing` from `apps/ios`                                                                                                                                                                                                         | Unavailable: `xcodebuild: command not found` (exit 127)                                                                                                                                                 |

`pnpm test --filter=@logyourbody/shared-lib` passed: 27 Vitest files / 109 cases
and 42 Node cases, including the final 11-case report suite with 100% production
line/branch/function coverage.

The report behavior suite is invoked by shared-lib's existing Vitest discovery,
under the normal root/Turbo test task. Production script and behavior cases live
inside that package so changes invalidate its task cache. No workflow, coverage
baseline, release selector, gate or branch protection was weakened.

## Native and provider qualification remains open

The existing compiled `AnalyticsServiceTests` file now contains these new cases:

- `testFirstInsightEligibilityAndDeduplicationThroughSanitizingPort`
- `testFirstInsightDropsEvenApprovedCrossEventMetadataAndSensitiveValues`
- `testVisibleRevealEmitsGenericImpressionThroughSanitizingPort`
- `testCalculationAndTransitionDoNotConsumeRenderQualification`
- `testMountedLoadingFallbackNeverEmitsImpression`

Existing all-event privacy cases also exercise the new marker. These native
cases have **not executed here**. The real Mac Unit/Launch Quality runners must
attach current-head execution, named passing cases and same-selector coverage
nonregression receipts. Existing native UI, Golden Path, eval and function
coverage gates remain mandatory. No new Swift file or target membership is needed.

Installed/TestFlight proof must identify build + source commit and controlled
staff gate state, show the actual reveal and edit/revisit, denied/empty/offline
inputs, foreground/background and reduced-motion/large-text behavior, and inspect
the sanitized marker. Retain production/exclusion coverage separately. A local
hosting test, source assertion, calculation or navigation log cannot replace it.

LYB-134 still owns commissioned RevenueCat delivery/storage/retry/deduplication
receipts. LYB-138 still owns release/account actions, LYB-106/171 first-run/import
behavior, and LYB-56 native coverage. No production migration, provider write,
purchase, outreach, spend, price/trial change or takeover of an active PR occurred.
No commissioned provider receipt or actual customer outcome was available to this
run. The report explicitly cannot authenticate operator attestations or close
those requirements. **LYB-179 is not outcome-complete from this source handoff.**

GBrain query, `put logyourbody/lyb-179-growth-evidence-2026-10-16` and `get` of
that same slug each failed with exit 7 against `127.0.0.1:7801` (connection
refused). Neither durable persistence nor same-slug readback was verified.
