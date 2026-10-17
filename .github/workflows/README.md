# GitHub Actions Workflows

This directory supports fast trunk-based shipping. Required checks should prove a pull request can land; slower or judgment-heavy work should run as advisory automation or post-merge release validation.

## Required PR Gate

### `ci.yml`

Primary pull request workflow for `main`.

- Pull requests target `main`; `preview`, `production`, and `dev` are not active development branches. Pull requests and merge groups targeting `production` also run so the active "Production" ruleset's required `CI Summary` check cannot deadlock.
- `Detect Changes`: path filter for web/package and iOS changes (`.github/scripts/detect-changes.sh`, tested by `detect-changes.test.mjs`). A merge group diffs against its own base (the previous group's head), so a web-only group never inherits a queued iOS PR; iOS runs only when a file the iOS jobs read changed, and an unknown diff selects everything. Also audits the live repository branch rulesets (`verify-ruleset-targets.mjs`) so quoted or missing ref targets cannot silently unprotect `main`/`production`.
- `JavaScript/TypeScript`: runs `pnpm install`, `pnpm lint`, `pnpm typecheck`, and `pnpm test:ci` when web, package, or CI harness files change. The job uses no privileged data-provider configuration, so pull request CI can verify buildability without credentials.
- `iOS` (Unit) and `iOS Launch Quality Gate`: each runs once, where it still gates the merge. Launch Quality runs on the PR head once the PR is ready for review (drafts defer it; `ready_for_review` reruns CI). Unit runs in the merge group, on the exact tree that lands; the group also runs Launch Quality when the entry's PR head has no passing Launch Quality run (e.g. entries enqueued before this split). While the `post-merge-lq-red` issue is open (see `ios-post-merge-quality.yml`), iOS merge groups run Launch Quality too, and an unknown hold state counts as held. A web-only change runs neither.
- `CI Summary`: aggregate required status. Branch protection should depend on this stable aggregate name rather than individual implementation jobs.

`CI Summary` is the normal hard merge gate. Keep it deterministic and fast enough for agent throughput.

## `ios-post-merge-quality.yml`

Launch Quality for `main` after merge, on the latest SHA only (`cancel-in-progress`). It checks iOS inputs changed since the newest SHA this workflow verified (`detect-changes.sh` with that base), so a run cancelled by a newer push is still covered. A failure is retried once. A second failure opens or updates the `post-merge-lq-red` issue (`.github/scripts/post-merge-quality-report.sh`, tested by `post-merge-quality.test.mjs`), and the next passing SHA closes it. There is no auto-revert: Launch Quality failed in 15% of merge groups over 2026-10-06..13, nearly all timeouts and recurring flakes.

A cancelled first attempt with a skipped retry leaves Report green only when the live `main` ref differs from the run's SHA. It leaves the hold issue untouched; the cancelled quality job keeps the workflow cancelled, so the SHA is not selected as a verified base. Cancellation at the current main tip, an unreadable or malformed main ref, and any failure without a passing retry still fail closed.

## Merge Queue Auto-Land

`main` uses GitHub's native merge queue (ruleset "Main - Protect", `ALLGREEN`, `MERGE`, required check `CI Summary`, 60-minute check timeout). Two secret-boundaried workflows make landing hands-off:

1. **`native-merge-queue.yml` — enrollment.** After `CI` completes on a same-repo, non-draft PR (or when a draft is marked ready), it enqueues the PR at its exact green head with `enqueuePullRequest`. When the queue drops a PR (`dequeued`) whose head is unchanged and green, it re-enqueues it if the removal was a check timeout or the head's first failed merge group; a second failed group at one head is a poison and stays out for the lanes repair owner, and manual or merge-conflict removals are left alone. A changes-requested or missing-approval `UNPROCESSABLE` refusal is `NOT_ELIGIBLE` (`::notice`, exit 0). A conflicted or not-mergeable `UNPROCESSABLE` refusal is `SKIPPED` (`::notice` and a job summary, exit 0). Draft, permission, and every other enqueue error still fail the job. It runs in the pull-request-triggered context, so it must never checkout code or receive secrets (`.github/scripts/verify-merge-queue-policy.mjs` enforces this). The enrollment script is inline; this workflow does not call a helper.
2. **`merge-queue-token-enrollment.yml` — token re-enqueue.** GitHub creates no workflow runs for events caused by `GITHUB_TOKEN`, and the queue only honours checks from the `merge_group` event's own run, so a bot-owned entry never gets merge-group CI and times out. After enrollment completes (`workflow_run`), this job dequeues bot-owned entries and re-enqueues them with the machine-user secret `MERGE_QUEUE_TOKEN` after re-proving `CI Summary` on the exact head. It never checks out code and never runs on pull-request events; without the secret it is a no-op.

`ALLGREEN` batches every queued entry, so one bot-owned entry blocks the batch. Manual recovery while the secret is absent: `gh pr merge <n> --merge --auto` with a user token (a user-token enqueue starts merge-group CI natively); a stuck entry can be removed with the `dequeuePullRequest` mutation first. While the secret is absent the Jovie lanes LYB binding does this automatically: it re-enqueues green bot-owned entries and dropped green PRs with its user token.

## Advisory Automation

### `codeowners-check.yml`

CODEOWNERS drift check on pushes to main that change a CODEOWNERS file, and on manual dispatch. Upserts JOV-7549 (`remediation:codeowners-drift`) with a comment for this repository when the file is missing or an owner is invalid. Live filing requires repository variable `REMEDIATION_TRIGGERS_ENABLED` to be `true` and `LINEAR_API_KEY`. Otherwise the job dry-runs.

### `advisory-ai-review.yml`

Non-blocking internal AI review for pull requests after the `CI` workflow completes.

- Uses OpenRouter through `.github/scripts/advisory-ai-review.mjs`.
- Posts a sticky PR comment named `Advisory / AI Review`.
- Defaults to `openrouter/free` unless repository variables override the model/router.
- Skips sensitive path diffs by default.
- Never checks out untrusted pull request code in a privileged context.
- Must not be added as a required status check.

Useful repository variables:

| Variable                              | Purpose                                                               |
| ------------------------------------- | --------------------------------------------------------------------- |
| `OPENROUTER_REVIEW_MODELS`            | Comma-separated fallback model/router list.                           |
| `OPENROUTER_REVIEW_MODEL`             | Single model/router fallback; defaults to `openrouter/free`.          |
| `OPENROUTER_PROVIDER_DATA_COLLECTION` | Provider policy; defaults to `deny`.                                  |
| `AI_REVIEW_MAX_DIFF_CHARS`            | Maximum diff sent to the model; defaults to `60000`.                  |
| `AI_REVIEW_ALLOW_SENSITIVE`           | Set `true` only for trusted model/provider review of sensitive paths. |
| `AI_REVIEW_COMMENT_ON_SKIP`           | Set `true` if skipped reviews should still post a PR comment.         |

Required secret:

| Secret               | Purpose                                            |
| -------------------- | -------------------------------------------------- |
| `OPENROUTER_API_KEY` | Authenticates advisory review calls to OpenRouter. |

### `codex-auto-fix-ci.yml`

Retired to `workflow_dispatch` only; the Jovie lanes LYB binding owns PR repair (see `BRANCH_FLOW.md`).
Historically it opened a repair pull request when the primary `CI` workflow failed on a pull request.

- Uses `openai/codex-action`.
- Requires `OPENAI_API_KEY`.
- Skips forked pull requests.
- Opens `codex/auto-fix-<run_id>` against the contributor branch.
- Does not push directly to `main`.

## Release Workflows

### `deploy.yml`

Runs after changes land on `main`. The web job installs, validates, builds, and deploys a prebuilt Vercel production artifact from GitHub Actions. Vercel Git deployments stay disabled on `main`, while non-main branches can produce the required Preview deployments through the existing GitHub integration.

### `web-release-loop.yml`

Reusable/manual web release loop. This is no longer the automatic main-branch release path.

### `ios-release-loop.yml`

Reusable/manual iOS release loop for TestFlight/App Store release paths.

### `app-store-metadata-sync.yml`

Uploads committed Fastlane metadata to App Store version 1.2.0 with deliver (`skip_binary_upload`, no screenshots, no submit, no build attach). It runs on a push to `main` that changes this workflow or `apps/ios/fastlane/metadata/**`.

### `app-store-connect-readiness.yml`

Read-only App Store Connect check for version 1.2.0. It runs on a push to `main` that changes this workflow or Fastlane metadata, daily at 16:00 UTC, on `workflow_dispatch`, and after `app-store-metadata-sync.yml` succeeds. It reports version state, whether the newest TestFlight upload is processed and selectable, whether both pro1 subscriptions are Ready to Submit or already attached, and whether What's New and storefront metadata match the committed manifest. It does not submit, attach a build, or write metadata.

### `ios-testflight-deploy.yml`

Reusable TestFlight deployment workflow.

Upload no longer blocks the job on App Store Connect processing. After the IPA is accepted, `distribute_testflight` waits and assigns groups. If that wait times out, re-run this workflow with `resume_only` plus the same `version_name` / `build_number` instead of building a new timestamped binary. Job timeout is 90 minutes.

Release workflows are app-specific and can be stricter than PR CI because they run after a change has already cleared the merge contract.

## Scheduled and Security Workflows

### `codeql-analysis.yml`

CodeQL analysis on pushes, pull requests, and schedule.

### `security-scan.yml`

Main-branch push and manual secret, dependency, and SBOM scanning. No clock. Gitleaks runs through the shared `JovieInc/ci` `secret-scan.yml` workflow, pinned by commit SHA. Main pushes fail on findings introduced by the pushed commit range; manual runs retain the full-history audit.

### `dependabot-auto-merge.yml`

Attempts to auto-merge Dependabot patch/minor updates after CI passes.

### `regenerate-certificates.yml`

Manual iOS certificate regeneration. No schedule. The job fails immediately unless the dispatch confirm is `NUKE-AND-REGENERATE` (LYB-74). Slack runs only when repository variable `CERT_REGEN_SLACK_ENABLED` is `true`.

## Blocking vs Advisory

Blocking checks:

- Deterministic install, lint, typecheck, test, and build failures.
- iOS compile/release-path failures when iOS files changed.
- Secret leaks and concrete security failures.
- Unsafe workflow permission changes.
- Auth, billing, RevenueCat, App Store, signing, or migration changes with concrete release-breaking evidence.

Advisory checks:

- AI code review without deterministic evidence.
- Style, architecture, or maintainability suggestions.
- Performance and accessibility suggestions without measured regression.
- Follow-up cleanup and test coverage ideas.

When advisory review finds a noncritical issue, open a focused follow-up PR or issue instead of delaying a landable PR.

### Shared Mac qualification

The required `iOS` and `iOS Launch Quality Gate` jobs always use standard hosted
`macos-15`. Their execution and signing paths are independent of shared Mac
availability, heartbeat state, and `MAC_RUNNER`; setting that variable cannot
reroute either required job. Existing tests and quality gates remain required.

Self-hosted Macs are optional capacity pending successful setup qualification and
measured pickup time, execution time, and reliability benefit. A fresh heartbeat
is not a capacity reservation: a Mac can become busy or disappear after the
probe, and GitHub does not switch a queued self-hosted job to hosted macOS. Job
execution timeouts do not bound that queue wait. No dispatcher or duplicate
product/release execution path is introduced.

The shared Mac workflow is manual only and cannot gate required CI. After it is
on `main`, request a secretless setup canary explicitly:

```sh
gh workflow run mac-runner-heartbeat.yml --repo JovieInc/LogYourBody --ref main \
  -f verify-ios-setup=true
```

Inspect the **Self-hosted iOS setup canary** job, its recorded runner name, and
Xcode, pinned SwiftLint, xcbeautify, Ruby/Bundler and `bundle check` output. Setup
or heartbeat success alone does not demonstrate shipping benefit or authorize
routing required builds onto the shared Macs.

CI tests this hosted policy and the diagnostic heartbeat helpers with Bashcov
4.0.0, requiring at least 80% executed-line coverage for each helper. The coverage
check rejects missing scripts, zero-line reports and reused suite records.
