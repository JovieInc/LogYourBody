# Launch policy mutation testing

`pnpm test:mutation` runs 14 curated semantic mutants against two launch-critical
JavaScript modules: private growth evidence qualification and release CI evidence
selection. The existing required shared-lib suite also executes the campaign and
the runner's regression tests, so `pnpm test` enforces it. No vendor account,
production data, network request or additional dependency is required.

The runner copies the source and its real behavior tests into temporary directories,
checks an unmodified passing baseline with coverage, and applies one unique source
edit at a time. The working source is never modified. Each mutant must compile and
produce actual assertion failures; survivors, stale/ambiguous anchors, invalid
syntax, infrastructure errors, timeouts, incomplete test runs and failed baselines
fail the command. They never inflate the killed count. The report retains the exact
source/test hashes, selector, coverage, test counts and assertion names.

The JSON receipt is `coverage/mutation/report.json` (ignored by Git). Normal test
caching includes the manifest, harness and external release-policy sources, and
restores the report. The explicit mutation command always executes afresh.

| Target           | Mutants | Baseline coverage floors: lines / branches / functions |
| ---------------- | ------- | ------------------------------------------------------ |
| Growth evidence  | 7       | 90% / 85% / 100%                                       |
| Release evidence | 7       | 80% / 95% / 100%                                       |
| Runner behavior  | —       | 90% / 95% / 100%                                       |

Growth mutants exercise production-only input, duplicate receipts, commissioning,
reconciliation, cohort maturity, duplicate JSON keys and conversion arithmetic.
Release mutants exercise source/repository identity, newest-run ordering, queue
reuse, job provenance, skipped summary and failed-run rejection. The release
campaign selects the ten policy tests. Existing full shell integration tests remain
in their original CI gate; the campaign does not claim those shell paths as covered.

Add a meaningful production change to `scripts/mutation/targets.json`, using an
exact unique anchor and a test that fails because behavior changes. Do not suppress
a survivor or turn a runtime error into a kill. If a mutation is equivalent,
replace it with a reviewed meaningful mutation and preserve the evidence in the
change description. Add tests for surviving meaningful mutants before release.

This is a bounded launch-policy campaign, not whole-app mutation coverage. It does
not measure Swift, UI, HealthKit, payments, performance or production conversion.
Native XCTest execution, same-selector coverage nonregression, StoreKit and UI
acceptance still require the real macOS runner. The committed native floors are
26,397/103,629 lines for quality-unit and 21,069/103,629 for unit-tier; neither is
full native coverage, and these selectors must not be combined.

The existing web Jest configuration now enforces a whole-source nonregression
floor during both normal `test` and `test:ci` runs. Its unchanged source inventory
measured 141 passing suites / 1,409 tests in this launch audit:

| Metric     | Covered / total | Measured | Enforced floor |
| ---------- | --------------- | -------- | -------------- |
| Statements | 7,561 / 13,890  | 54.43%   | 54.4%          |
| Branches   | 5,576 / 9,936   | 56.11%   | 56.1%          |
| Functions  | 1,543 / 2,719   | 56.74%   | 56.7%          |
| Lines      | 6,829 / 12,210  | 55.92%   | 55.9%          |

These are measured floors, not a claim of full coverage or the aspirational 80%
web target. Preserve every retained production source in `collectCoverageFrom`.
Raise floors only after a complete measured suite passes. Review
`apps/web/coverage/coverage-summary.json` and the LCOV report for remaining gaps;
the separate voice-adapter command and browser tests retain their existing gates
and are not included in these Jest percentages. When deliberately running only
selected tests, use the existing direct Jest invocation without `--coverage`;
partial-suite coverage cannot establish or update a whole-web baseline.

In the managed Linux environment, use the pinned runtime from
`source /workspace/.cloud-setup/activate.sh logyourbody`. Local test subprocesses
may require sandbox approval. `NODE_NO_WARNINGS=1` suppresses the injected proxy
runtime warning when exercising CLI tests that assert exact stderr; keep the proxy
and all credential/network environment settings intact.
