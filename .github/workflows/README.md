# GitHub Actions Workflows

This directory supports fast trunk-based shipping. Required checks should prove a pull request can land; slower or judgment-heavy work should run as advisory automation or post-merge release validation.

## Required PR Gate

### `ci.yml`

Primary pull request workflow for `main`.

- `Detect Changes`: path filter for web/package and iOS changes.
- `JavaScript/TypeScript`: runs `pnpm install`, `pnpm lint`, `pnpm typecheck`, and `pnpm test:ci` when web, package, or CI harness files change. The job supplies syntactically valid placeholder Clerk/Supabase values when repository secrets are unavailable so pull request CI can verify buildability without privileged credentials.
- `iOS`: runs the iOS Fastlane CI lane when iOS files change.
- `CI Summary`: aggregate required status. Branch protection should depend on this stable aggregate name rather than individual implementation jobs.

`CI Summary` is the normal hard merge gate. Keep it deterministic and fast enough for agent throughput.

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

Runs after changes land on `main` and handles production deployment work.

### `web-release-loop.yml`

Reusable/manual web release loop.

### `ios-release-loop.yml`

Reusable/manual iOS release loop for TestFlight/App Store release paths.

### `ios-testflight-deploy.yml`

Reusable TestFlight deployment workflow.

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
