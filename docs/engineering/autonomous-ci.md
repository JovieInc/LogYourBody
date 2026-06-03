# Autonomous CI and Review Policy

LogYourBody uses a fast-shipping CI model: merge-blocking checks should prove that a change can safely land, while advisory automation should create follow-up work without parking pull requests.

This policy is intentionally compatible with Jovie's harness model so common CI improvements can be shared across repositories.

## Required Gates

Only deterministic release-breakers should block merges:

- `CI Summary`: aggregate status for changed-path install, lint, typecheck, tests, and iOS validation.
- Security or secret checks when they produce concrete evidence.
- Migration, release-signing, App Store, RevenueCat, Clerk, Supabase, or workflow changes that can break production and have a reproducible failure mode.
- Fork safety checks for untrusted pull requests.

If a risk is subjective, stylistic, speculative, or not backed by a command/policy violation, it belongs in advisory review.

## Advisory Review

`Advisory / AI Review` replaces external review bots such as CodeRabbit and gReptile as the default AI review surface. It is not a branch-protection requirement.

Advisory review may:

- Summarize the PR risk.
- Call out deterministic release blockers for humans or agents to verify.
- Suggest follow-up PRs or issues.
- Recommend targeted commands to run.

Advisory review must not:

- Push commits, approve, merge, deploy, or change branch protection.
- Receive secrets or privileged production data.
- Block a merge on model judgment alone.
- Review sensitive diffs through free or alpha third-party models unless explicitly enabled.

## OpenRouter Model Policy

Model selection lives in repository variables so the workflow can change providers without code edits:

- `OPENROUTER_REVIEW_MODELS`: comma-separated fallback list for reliable advisory review.
- `OPENROUTER_REVIEW_MODEL`: single model/router fallback. Defaults to `openrouter/free`.
- `OPENROUTER_PROVIDER_DATA_COLLECTION`: defaults to `deny`.
- `AI_REVIEW_ALLOW_SENSITIVE`: defaults to `false`; keep it false unless a trusted model/provider policy is configured.

Free or alpha models are acceptable for non-sensitive advisory classification, summary, duplicate detection, and follow-up drafting. They are not acceptable as release gates or code mutation agents.

## Follow-Up Bias

When advisory review finds noncritical issues, agents should open focused follow-up PRs rather than expanding the current PR. The expected loop is:

1. Required CI proves the PR is landable.
2. Advisory review ranks residual risks.
3. Noncritical findings become labels, issues, or small follow-up PRs.
4. Repeated advisory findings become deterministic tests, lint rules, or harness policy.

## Shared CI Direction

The target cross-repo shape is:

- `CI / PR Ready`: one required aggregate for ordinary PRs.
- `CI / Migration Guard`: required only when schema or migration paths change.
- `Fork PR Gate`: required where untrusted code could otherwise reach privileged automation.
- `Advisory / AI Review`: non-blocking OpenRouter/internal AI review.
- `Agent Remediation`: opens repair PRs for blocking failures.
- `Nightly Quality`: slow security, dependency, coverage, visual, performance, and flake checks.

Repository-specific release gates stay local: LogYourBody owns Fastlane, RevenueCat, App Store, and iOS signing gates; Jovie owns its web deployment, Sentry, and product-specific smoke gates.
