# Codex setup for Log Your Body

Read `AGENTS.md` first. Run `bash scripts/codex-setup.sh` from any directory.
The wrapper selects the already-installed nvm version in `.nvmrc` when available.
The bootstrap verifies that exact Node version and the `packageManager` pnpm
pin, then runs `pnpm install --frozen-lockfile --prefer-offline` from
the repository root. It never creates placeholder secrets, runs migrations,
provisions services, or treats a build/test failure as successful setup.

The current source pins Node 22.23.2 and pnpm 10.34.1. Keep the separate Eve
Node 24 runner in `scripts/eve/run-node24.sh`; it has a different runtime role.

`.codex/environments/environment.toml` supplies the desktop worktree setup,
cleanup report, and common actions using the app's `script` and `[[actions]]`
schema. `.codex/hooks.json` supplies SessionStart and Stop. Codex requires
review and trust of each new hook definition through `/hooks`; do not fabricate
trust hashes or bypass review. Manual setup remains available before trust.

Stop and desktop cleanup preserve source, dependencies, build outputs, and
shared Git metadata. A turn ending is not a worktree release. For a managed
Codex worktree, use Codex's archive operation, which saves a recoverable Git
snapshot. Certificate helpers under `scripts/archive/` are separate signing
operations and are never invoked by lifecycle cleanup.

Cloud install scripts must install/activate the source-pinned Node and pnpm
toolchain before invoking this bootstrap. Setup shell exports do not carry
into later shells: retain the toolchain on disk and activate its PATH in the
environment's Start skill. Refresh frozen dependencies after a checkout or
lockfile change. Native iOS, signing, HealthKit, authenticated services, and
release acceptance need their own environments and receipts.

Use GPT-6.1 Sol at medium for general implementation and Opus 5.5 at medium
for Claude Code. Increase effort for a measured correctness gap; use a cheaper
supported model for bounded routine work. Discover available models from the
actual client/account and verify new IDs against the provider's documentation.
Do not infer account access from a model's public availability.

Verification: `node --test --experimental-test-coverage
--test-coverage-include=scripts/codex-setup.mjs --test-coverage-lines=90
--test-coverage-branches=90 --test-coverage-functions=100
scripts/codex-setup.test.mjs`. The same gate runs in CI's change-detection job.
