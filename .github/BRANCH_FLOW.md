# LogYourBody Branch Flow

LogYourBody uses trunk-based development. `main` is the single production trunk; all work lands through short-lived pull requests.

## Branch Model

```
feat/*, fix/*, refactor/*, agent/* -> pull request -> main
```

- `main`: protected production trunk.
- `feat/*`: new user-visible or product behavior.
- `fix/*`: bug fixes and release repairs.
- `refactor/*`: structure-only changes with no intended behavior change.
- `agent/*`: agent scratch or automation branches.
- `codex/*`: generated repair branches opened by Codex automation.

There is no long-lived `dev` branch in the active process. `preview` and `production` may exist as deployment environments or legacy branch names, but agents should not treat them as the normal development lane.

Pull requests should target `main`. CI is configured around `main` as the trunk, and agents should not open routine product or release PRs against `preview`, `production`, or other staging branches.

## Merge Contract

Pull requests into `main` should be small and focused. The required merge signal is the aggregate `CI Summary` status from `.github/workflows/ci.yml`.

`CI Summary` fails only when changed-path deterministic validation fails:

- Web/package changes: `pnpm install`, `pnpm lint`, `pnpm typecheck`, `pnpm test:ci`.
- iOS changes: the iOS Fastlane CI lane.
- The summary job itself if required upstream validation fails.

External or AI review comments are advisory unless they point to a deterministic release-breaker such as a failing command, leaked secret, unsafe workflow permission change, crash-on-launch risk, data loss, or broken auth/billing/release path.

## Advisory Review

`Advisory / AI Review` is the internal replacement lane for external review bots such as CodeRabbit and gReptile. It posts a sticky, non-blocking pull request comment after CI runs.

Use advisory findings this way:

- Fix release-blockers in the current PR if they include concrete evidence.
- Convert noncritical findings into follow-up issues or small PRs.
- Promote repeated findings into deterministic tests, lint, or CI harness rules.

The advisory reviewer should not become a branch-protection requirement.

## Autonomous Repair

When required CI fails, `.github/workflows/codex-auto-fix-ci.yml` can open a focused repair PR back to the failing branch. It must not push to `main` directly.

Agents should prefer repair PRs and follow-up PRs over expanding an already-landable PR.

## Local Validation

Run common validation from the repository root:

```bash
pnpm install
pnpm lint
pnpm typecheck
pnpm test:ci
```

For iOS-specific work:

```bash
cd apps/ios
bundle exec fastlane ci_ios
```

## Sensitive Paths

Changes in these areas deserve extra scrutiny and may block unattended automation:

- `.github/**`
- Authentication, Clerk, Supabase, and session handling
- Billing, RevenueCat, StoreKit, App Store, subscriptions, and entitlements
- iOS signing, provisioning, Fastlane, and release metadata
- Database migrations and destructive data paths
- Secrets, credentials, environment files, and production configuration
