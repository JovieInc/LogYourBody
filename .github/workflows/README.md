# Three-Loop CI/CD System

This repository uses a three-loop CI/CD system designed for rapid feedback, comprehensive testing, and safe production deployments.

## Overview

```
dev branch → Rapid Loop → Alpha/Preview Deployments (< 5 min)
    ↓
preview branch → Confidence Loop → Beta/Staging Deployments (nightly)
    ↓
main branch → Release Loop → Production Deployments (manual)
```

## 🚀 Rapid Loop (dev branch)

**Goal**: Fast feedback for developers  
**Target Time**: < 5 min for web, < 15 min for iOS  
**Deployments**: Vercel Alpha, TestFlight Alpha (internal only)

### Workflows

- `web-rapid-loop.yml`: Lint, type-check, unit tests → Vercel deploy
- `ios-rapid-loop.yml`: SwiftLint, smoke tests → TestFlight Alpha

### Features

- Runs on every push to dev branch
- Minimal test suite (smoke tests only)
- Timestamp + SHA versioning
- Auto-deploys for immediate testing

## 🛡️ Confidence Loop (preview branch)

**Goal**: Catch quality issues before release  
**Schedule**: Nightly at 2 AM PT (9 AM UTC) or on-demand  
**Deployments**: Vercel Beta, TestFlight Beta (external testers)

### Workflows

- `web-confidence-loop.yml`: E2E tests, Lighthouse, accessibility → Vercel Beta
- `ios-confidence-loop.yml`: Full UI tests, sanitizers, snapshots, performance → TestFlight Beta

### Features

- Comprehensive test suite
- Performance profiling
- Memory leak detection (iOS)
- Visual regression testing
- Slack notifications on failure

## 🎯 Release Loop (main branch)

**Goal**: Production-ready deployments  
**Trigger**: Manual PR from preview → main  
**Deployments**: Vercel Production, App Store

### Workflows

- `web-release-loop.yml`: Validates preview is green → Production deploy
- `ios-release-loop.yml`: Builds release → TestFlight/App Store

### Features

- Requires all preview checks passing
- Creates GitHub releases and tags
- Supports phased rollouts
- Post-deployment validation

## 🔄 Supporting Workflows

### main-orchestrator.yml

Central dispatcher that:

- Detects which files changed (web/iOS/docs)
- Routes to appropriate loop based on branch
- Provides unified `ci-summary` status check

### promote-preview.yml

Automatic promotion from dev → preview:

- Triggers when dev CI passes
- Creates/updates PR automatically
- Enables auto-merge when checks pass
- Mentions @JovieInc for visibility

### dependabot-auto-merge.yml

Handles dependency updates:

- Auto-approves minor/patch updates
- Requires manual review for major updates
- Runs security checks before merge

### codex-auto-fix-ci.yml

Uses Codex to repair failed PR checks automatically:

- Triggers when the primary `CI` workflow finishes with a failure on a pull request
- Checks out the failing commit, installs pnpm dependencies, and calls the official `openai/codex-action` to craft a minimal fix
- Re-runs the test suite and opens a reviewable PR from `codex/auto-fix-<run_id>` back to the contributor branch; forked PRs are skipped with a status comment

## Branch Protection

All branches use `ci-summary` as the required status check:

- **dev**: No PR reviews (optimized for speed)
- **preview**: 0 reviews required (enables auto-merge)
- **main**: 1 review + code owners (production safety)

## Configuration

### Codex Auto-Fix prerequisites

- `OPENAI_API_KEY` must be set as a repository or organization secret so Codex can authenticate.
- The default `GITHUB_TOKEN` needs `contents` and `pull-requests` write permissions (granted in the workflow) so the action can create branches and open PRs.
- Forked pull requests are skipped automatically; maintainers can cherry-pick from a maintainer branch if Codex needs to be run manually.

### Environment Variables

#### Web Deployments

- `VERCEL_TOKEN`: Vercel authentication
- `VERCEL_ORG_ID`: Organization ID
- `VERCEL_PROJECT_ID`: Project ID
- `{ENV}_SUPABASE_URL`: Supabase URL per environment
- `{ENV}_SUPABASE_ANON_KEY`: Supabase anon key
- `{ENV}_CLERK_PUBLISHABLE_KEY`: Clerk public key
- `{ENV}_CLERK_SECRET_KEY`: Clerk secret key

#### iOS Deployments

- `IOS_P12_BASE64`: Code signing certificate
- `IOS_P12_PASSWORD`: Certificate password
- `IOS_PROVISIONING_PROFILE_BASE64`: Provisioning profile
- `ASC_API_KEY_JSON`: App Store Connect API key
- `APPLE_TEAM_ID`: Apple Developer Team ID
- `APP_STORE_APP_ID`: App Store app identifier

#### Notifications

- `SLACK_WEBHOOK_URL`: Slack webhook for confidence loop failures

### GitHub Environments

1. **development**: Used for dev branch deployments
2. **preview**: Used for preview branch deployments
3. **production**: Used for main branch deployments
4. **production-testflight**: iOS TestFlight releases
5. **production-app-store**: iOS App Store releases

## Usage

### Deploying Changes

1. **Development**: Push to `dev` branch
   - Rapid tests run automatically
   - Alpha builds deploy within minutes

2. **Staging**: Merge dev → preview (automatic)
   - Comprehensive tests run nightly
   - Beta builds available for testing

3. **Production**: Create PR preview → main
   - Requires manual approval
   - Deploys same tested artifacts

### Manual Workflows

#### Force iOS Release

```bash
gh workflow run ios-release-loop.yml \
  -f release_type=testflight
```

#### Run Confidence Tests

```bash
gh workflow run web-confidence-loop.yml
gh workflow run ios-confidence-loop.yml
```

## Monitoring

### Check Workflow Status

```bash
# View recent runs
gh run list --workflow=main-orchestrator.yml

# Watch specific run
gh run watch <run-id>
```

### View Deployments

- Web Alpha: https://dev-latest.logyourbody.com
- Web Beta: https://preview.logyourbody.com
- Web Production: https://logyourbody.com
- iOS: TestFlight app

## Troubleshooting

### Common Issues

1. **Rapid loop timeout**: Increase timeout in workflow or optimize tests
2. **Confidence loop failures**: Check Slack for detailed error reports
3. **Auto-merge not working**: Verify branch protection settings
4. **iOS signing errors**: Check certificate/profile expiration

### Debug Commands

```bash
# Check branch protection
gh api repos/JovieInc/LogYourBody/branches/{branch}/protection

# View workflow logs
gh run view <run-id> --log

# Re-run failed job
gh run rerun <run-id> --failed
```

## Best Practices

1. **Keep rapid tests fast**: Only critical smoke tests
2. **Fix flaky tests**: Don't ignore intermittent failures
3. **Monitor costs**: GitHub Actions and Vercel usage
4. **Regular cleanup**: Remove old artifacts and deployments
5. **Security**: Never commit secrets, use GitHub Secrets

---

For more information, see the individual workflow files or contact the maintainers.
