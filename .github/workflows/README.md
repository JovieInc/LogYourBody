# GitHub Actions Workflows

This directory supports fast trunk-based shipping. Required checks should prove a pull request can land; slower or judgment-heavy work should run as advisory automation or post-merge release validation.

## Required PR Gate

### `ci.yml`

Primary pull request workflow for `main`.

- Pull requests target `main`; `preview`, `production`, and `dev` are not active development branches.
- `Detect Changes`: path filter for web/package and iOS changes.
- `JavaScript/TypeScript`: runs `pnpm install`, `pnpm lint`, `pnpm typecheck`, and `pnpm test:ci` when web, package, or CI harness files change. The job uses no privileged data-provider configuration, so pull request CI can verify buildability without credentials.
- `iOS`: runs the iOS Fastlane CI lane when iOS files change.
- `CI Summary`: aggregate required status. Branch protection should depend on this stable aggregate name rather than individual implementation jobs.

`CI Summary` is the normal hard merge gate. Keep it deterministic and fast enough for agent throughput.

## Merge Queue Auto-Land

`main` uses GitHub's native merge queue (ruleset "Main - Protect", `ALLGREEN`, `MERGE`, required check `CI Summary`, 60-minute check timeout). Two secret-boundaried workflows make landing hands-off:

1. **`native-merge-queue.yml` — enrollment.** After `CI` completes on a same-repo, non-draft PR (or when a draft is marked ready), it enqueues the PR at its exact green head with `enqueuePullRequest`. It runs in the pull-request-triggered context, so it must never checkout code or receive secrets (`.github/scripts/verify-merge-queue-policy.mjs` enforces this).
2. **`merge-queue-token-enrollment.yml` — token re-enqueue.** GitHub creates no workflow runs for events caused by `GITHUB_TOKEN`, and the queue only honours checks from the `merge_group` event's own run, so a bot-owned entry never gets merge-group CI and times out. After enrollment completes (`workflow_run`), this job dequeues bot-owned entries and re-enqueues them with the machine-user secret `MERGE_QUEUE_TOKEN` after re-proving `CI Summary` on the exact head. It never checks out code and never runs on pull-request events; without the secret it is a no-op.

`ALLGREEN` batches every queued entry, so one bot-owned entry blocks the batch. Manual recovery while the secret is absent: `gh pr merge <n> --merge --auto` with a user token (a user-token enqueue starts merge-group CI natively); a stuck entry can be removed with the `dequeuePullRequest` mutation first.

## Advisory Automation

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

Opens a repair pull request when the primary `CI` workflow fails on a pull request.

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

### `ios-testflight-deploy.yml`

Reusable TestFlight deployment workflow.

Upload no longer blocks the job on App Store Connect processing. After the IPA is accepted, `distribute_testflight` waits and assigns groups. If that wait times out, re-run this workflow with `resume_only` plus the same `version_name` / `build_number` instead of building a new timestamped binary. Job timeout is 90 minutes.

Release workflows are app-specific and can be stricter than PR CI because they run after a change has already cleared the merge contract.

## Scheduled and Security Workflows

### `codeql-analysis.yml`

CodeQL analysis on pushes, pull requests, and schedule.

### `security-scan.yml`

Weekly/manual/main-branch secret, dependency, and SBOM scanning.

### `dependabot-auto-merge.yml`

Attempts to auto-merge Dependabot patch/minor updates after CI passes.

### `regenerate-certificates.yml`

iOS certificate and provisioning maintenance.

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
