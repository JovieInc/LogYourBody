# LogYourBody Codebase Guidelines

> **Source of truth**: This document consolidates all AI-assistant rules for LogYourBody (including the former `apps/ios/docs/development/CLAUDE.md` notes and `.windsurf/rules/ios-rules.md`). Update this file whenever process guidance changes so every agent uses a single, canonical reference.

## Repository Overview

LogYourBody is a comprehensive fitness tracking application with native iOS and web applications. The codebase follows a monorepo structure with shared utilities and independent app implementations.

### Directory Structure

```
LogYourBody/
├── apps/
│   ├── ios/           # Native iOS app (SwiftUI, Swift 5.9+)
│   └── web/           # Next.js web application
├── packages/          # Shared packages and libraries
│   ├── backend/       # Backend services (if applicable)
│   ├── shared-*/      # Shared utilities, types, and components
│   └── supabase/      # Shared Supabase client and types
├── .github/           # GitHub Actions workflows and configurations
└── docs/              # Project documentation
```

### Monorepo Setup

- **Package Manager**: pnpm (NEVER use npm or yarn)
- **Build System**: Turborepo for orchestrating builds, lints, tests, and typechecks
- **Root Scripts**: All common tasks run through root `package.json` scripts that leverage Turborepo

## Project Context

- **Mission**: Help users monitor weight, body composition, and progress photos with HealthKit integration and Supabase-backed sync.
- **Platforms**: Native iOS app (SwiftUI, Swift 5.9+) and Next.js web app share Clerk-based authentication.
- **Key Stacks**:
  - **Authentication**: Clerk SDK with browser-based OAuth for Apple Sign In.
  - **Design System**: iOS 26 Liquid Glass with graceful fallbacks.
  - **Data**: Core Data for local storage, Supabase for cloud sync, HealthKit for weight and step data.
  - **Feature Flags**: Statsig for controlled rollouts and A/B testing.

---

## Branching Model

### Production / Trunk Branch

- **`main`** is the single trunk and production branch.
- `main` must **always** be:
  - ✅ Green in CI
  - ✅ Deployable
  - ✅ Human-reviewed

### Branch Types

**No long-lived `dev` branch exists.** All work happens on short-lived branches off `main`:

- **Features**: `feat/<short-desc>`
  Example: `feat/new-onboarding`
- **Fixes**: `fix/<short-desc>`
  Example: `fix/paywall-crash`
- **Refactors**: `refactor/<area>-<short-desc>`
  Example: `refactor/metrics-layer`
- **Agent Scratch Branches** (if needed): `agent/<agent-name>/<short-desc>`
  Example: `agent/claude/explore-healthkit`

### Rules

1. **Agents and humans NEVER commit directly to `main`.**
2. **All changes flow via PRs into `main`.**
3. **Branches should be small and focused**, optimized for quick review and merge.
4. **Delete branches after merge** to keep the repository clean.

---

## Agents vs Humans

> **Rule of Thumb**: Agents propose; humans dispose. `main` only contains human-reviewed, CI-passing code.

### Agents May:

- Work only on non-`main` branches (`feat/*`, `fix/*`, `refactor/*`, `agent/*`).
- Make messy/frequent local commits while working (these will be cleaned up later).
- Attempt to run validation commands before declaring work complete:
  - `pnpm lint`
  - `pnpm typecheck`
  - `pnpm test` or `pnpm test:ci`
- Open draft PRs to share progress (but not merge them).

### Agents Must NOT:

- ❌ Push directly to `main`
- ❌ Merge PRs into `main`
- ❌ Change branch protection, CI configuration, or workflow files unless explicitly requested
- ❌ Bypass required checks or PR requirements
- ❌ Relax security or quality gates

### Humans:

- Review and curate agent changes.
- Clean up commit history (squash/rebase) before merging.
- Open and manage PRs targeting `main`.
- Decide which changes are merged and when.
- Approve and merge PRs after CI passes and review is complete.

---

## Commits and PRs

### Commit Messages

Use **Conventional Commits** style:

- `feat: add new onboarding flow`
- `fix: resolve paywall crash on iOS 17`
- `refactor: extract metrics layer into service`
- `chore: update dependencies`
- `test: add unit tests for sync manager`

Agents can generate these; humans may edit for clarity before merge.

### Commit Shape

- **For merge into `main`**: Prefer a small number of meaningful commits (1–3 clean commits per PR).
- **For large agent work**: Squash many agent commits into 1–3 clean commits before merge.

### PR Requirements

Every change to `main` must come via a **Pull Request** targeting `main`.

**PRs must**:

1. Be small and focused (single feature/fix/refactor).
2. Pass CI:
   - `js` job from `.github/workflows/ci.yml` (always required)
   - `ios` job if the change affects iOS code (when enabled/required)
3. Have at least **one human review** before merging.
4. Include a clear description of what changed and why.

### Merge Strategy

- **Prefer "Squash and merge"** for PRs into `main` to keep history clean.
- Agents must not bypass PR requirements or required checks.

---

## CI and Required Checks

### Core CI Commands (via pnpm + Turborepo)

Run these from the repository root:

```bash
pnpm install        # Install dependencies
pnpm lint           # Runs: turbo run lint
pnpm typecheck      # Runs: turbo run typecheck
pnpm test           # Runs: turbo run test
pnpm test:ci        # Runs: turbo run test -- --runInBand (for CI)
pnpm build          # Runs: turbo run build
```

For specific apps/packages, use filters:

```bash
pnpm --filter apps/web lint
pnpm --filter packages/backend test
```

### CI Workflows

#### `.github/workflows/ci.yml` (PR Checks)

Runs on **all PRs to `main`**. Required jobs:

- **`js` job** (always required):
  - `pnpm install`
  - `pnpm lint`
  - `pnpm typecheck`
  - `pnpm test:ci`
- **`ios` job** (when relevant/required):
  - iOS-specific tests and builds

**PRs into `main` must pass these checks before merge.**

#### `.github/workflows/deploy.yml` (Deployment)

Runs on **pushes to `main`** (after merge). Jobs:

- **`web` job**:
  - `pnpm install`
  - `pnpm lint`
  - `pnpm typecheck`
  - `pnpm test:ci`
  - `pnpm --filter apps/web build`
  - Deploy to Vercel
- **`ios-beta` job** (optional, usually disabled):
  - iOS beta deployment via Fastlane

### Branch Protection

- **`main` is protected**:
  - ❌ No direct pushes
  - ✅ Required status checks from `ci.yml` must pass before merge
  - ✅ At least one human review required
- **Agents must assume**:
  - Any PR that doesn't pass `ci.yml` will be rejected.
  - They cannot and should not relax branch protection.

### Agent Responsibilities

- **Always use `pnpm`**, never `npm` or `yarn`.
- **Rely on root scripts** (`pnpm lint`, `pnpm typecheck`, etc.) instead of inventing new command entrypoints.
- **Keep workflow names and job names stable** once they are referenced by branch protection/rulesets.
- **Do not introduce conflicting script patterns** (e.g., running `eslint` directly instead of via `pnpm lint`).

---

## Feature Flags & Safety (Statsig)

### Core Principle

**Any user-visible or risky change must be behind a Statsig feature gate.**

### Gate Naming Examples

- `new_onboarding_v2`
- `new_dashboard_v2`
- `strict_reminders`
- `enable_healthkit_sync`

### Pattern for Changes

1. **Implement new logic behind a Statsig gate.**
2. **Default gate OFF** for production users.
3. **Internal testing**: Enable for staff/test users via Statsig console.
4. **Gradual rollout**: 1% → 10% → 50% → 100%, controlled outside code.

### Agent Rules

- ✅ Respect existing gates.
- ✅ Add new gates for new behavior rather than rewriting code to bypass gates.
- ❌ Never hard-code permanent "new behavior" without a gate if it is risky or user-facing.
- ❌ Never remove or bypass existing feature gates without explicit human approval.

**Example**:

```typescript
// Good: Feature-gated new behavior
if (statsig.checkGate('new_onboarding_v2')) {
  return <NewOnboardingFlow />;
}
return <LegacyOnboardingFlow />;

// Bad: Hard-coded new behavior
return <NewOnboardingFlow />; // ❌ No gate!
```

---

## Monorepo + pnpm/Turbo Expectations

### Package Manager

- **Always use `pnpm`**, never `npm` or `yarn`.
- Check `pnpm-lock.yaml` into git, not `package-lock.json` or `yarn.lock`.

### Monorepo Commands

From the **repository root**:

```bash
pnpm install        # Install all dependencies
pnpm lint           # Lint all packages
pnpm typecheck      # Type-check all packages
pnpm test           # Run all tests
pnpm test:ci        # Run all tests in CI mode
pnpm build          # Build all packages/apps
```

For **specific apps/packages**, use filters:

```bash
pnpm --filter apps/web lint
pnpm --filter apps/web build
pnpm --filter packages/backend test
pnpm --filter packages/shared-ui typecheck
```

### Do Not Introduce

- ❌ New package managers (npm, yarn, bun, etc.)
- ❌ Conflicting script patterns (e.g., running `eslint` or `tsc` directly instead of via `pnpm lint` or `pnpm typecheck`)
- ❌ Workspace-level scripts that bypass Turborepo caching

### Align with Existing Scripts

Agents must align with existing scripts instead of inventing new command entrypoints for common tasks. If a script doesn't exist, propose adding it to the root `package.json` rather than running tools directly.

---

## Platform-Specific Guidelines

The sections below provide platform-specific details for iOS and web development. Always follow the general workflow rules above (branching, PRs, CI, feature flags) regardless of platform.

## Working with the iOS App

### Key Directories

- `apps/ios/LogYourBody/` - Main iOS application code
  - `Views/` - SwiftUI views and UI components
  - `Models/` - Data models and Core Data entities
  - `Services/` - Business logic and API services
  - `Managers/` - Singleton managers (Auth, Sync, CoreData, etc.)
  - `Utils/` - Utility functions and extensions
  - `Resources/` - Assets, fonts, and static resources

### Important Files

- `LogYourBody.xcodeproj` - Xcode project file
- `Supabase.xcconfig` - Supabase configuration (not in git)
- `LogYourBody/Config.xcconfig` - App configuration (not in git)
- `CLAUDE.md` - Legacy iOS-specific AI assistant context (all guidance now mirrored here)

### Validation Commands

When making iOS changes, run these commands from `apps/ios/`:

```bash
# Lint Swift code
swiftlint lint --strict

# Build for testing
xcodebuild -project LogYourBody.xcodeproj \
  -scheme LogYourBody \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build-for-testing

# Run tests
xcodebuild -project LogYourBody.xcodeproj \
  -scheme LogYourBody \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test
```

## Working with the Web App

### Key Directories

- `apps/web/` - Next.js application
  - `app/` - App router pages and layouts
  - `components/` - React components
  - `lib/` - Utilities and shared logic
  - `public/` - Static assets

### Validation Commands

**Always run from the repository root** using Turborepo scripts:

```bash
pnpm install            # Install all dependencies
pnpm lint               # Lint all packages including web
pnpm typecheck          # Type-check all packages including web
pnpm test               # Run all tests including web
pnpm test:ci            # Run all tests in CI mode
pnpm build              # Build all packages/apps
```

To run commands for **web app only**, use filters:

```bash
pnpm --filter apps/web lint
pnpm --filter apps/web typecheck
pnpm --filter apps/web test
pnpm --filter apps/web build
```

## Code Style Guidelines

### Swift (iOS)

- Follow Apple's Swift API Design Guidelines
- Use SwiftUI for all new UI code
- Prefer value types (structs) over reference types (classes)
- Use `@MainActor` for UI-related code
- Follow existing patterns in the codebase
- Use meaningful variable and function names
- Add comments only when the code isn't self-explanatory
- Keep each screen/view/controller focused on a single responsibility. If a screen contains distinct sections, repeated patterns, or section-specific state/logic, split it into subviews/components and move non-UI logic into a ViewModel. Use line counts only as guardrails: aim for ≤500 lines per view/controller and ≤40 lines per function; refactor into named components when exceeding those limits. Always reuse existing components instead of re-implementing near-identical UI.
- Typography: stick to SF Pro / system fonts (or Inter where specified) for a confident, neutral tone.
- Color palette: blacks, whites, and neutral grays with subtle accent colors reserved for UX cues (progress indicators, toggles, CTA states).
- Backgrounds: true or near-black Liquid Glass surfaces; ensure text respects AA contrast in light and dark modes.
- Copywriting: concise, Apple-style language—capitalize sparingly and avoid filler text.
- Accessibility: test against Dynamic Type, avoid low-contrast combinations, and never rely on color alone for meaning.

### TypeScript/React (Web)

- Use TypeScript strict mode
- Prefer functional components with hooks
- Use Tailwind CSS for styling
- Follow Next.js App Router conventions
- Handle loading and error states properly
- Use React Server Components where appropriate

## Design System

### iOS Design Guidelines

- Follow iOS 26 Liquid Glass design system
- Use system colors and materials
- Ensure proper dark mode support
- Maintain 60fps scrolling performance
- Support Dynamic Type for accessibility
- Test on both iPhone and iPad
- See the Swift guidelines above for typography, color, copywriting, and accessibility guardrails that were previously maintained in `CLAUDE.md`.

### Web Design Guidelines

- Mobile-first responsive design
- Use the established color palette
- Maintain consistency with iOS app
- Ensure WCAG AA accessibility compliance
- Optimize for Core Web Vitals

## Authentication & Data

### Authentication Flow

- iOS: Clerk SDK with browser-based OAuth for Apple Sign In
- Web: Clerk with multiple providers
- Both platforms share the same user accounts

### Data Persistence

- iOS: Core Data for local storage, Supabase for cloud sync
- Web: Supabase for all data operations
- Sync is handled automatically by the SyncManager (iOS)

## Testing

### Test Coverage Requirements

- iOS: Minimum 70% code coverage
- Web: Minimum 80% code coverage
- All new features must include tests

### Running Tests

From the repository root:

```bash
pnpm test           # Run all tests
pnpm test:ci        # Run all tests in CI mode (sequential, for CI environments)
```

For specific apps/packages:

```bash
pnpm --filter apps/web test
pnpm --filter packages/backend test
```

For iOS tests, see "Working with the iOS App" section above.

## Migration Notes

### Current Migrations

1. **iOS Code Signing**: Moving to Fastlane Match for certificate management
2. **CI Performance**: Migrating to macOS-14 runners for better performance
3. **Design System**: Updating to iOS 26 Liquid Glass design patterns

---

## Working with AI Agents

### Context Files

- Reference this `agents.md` for _all_ AI-assistant guidance. Other docs (e.g., `CLAUDE.md`, `.windsurf/rules/ios-rules.md`) now simply point back here.
- Update this file whenever process guidance changes.

### Best Practices

1. **Exploration**: Use grep/glob tools to understand code structure before making changes.
2. **Validation**: Always run `pnpm lint`, `pnpm typecheck`, and `pnpm test` before declaring work complete.
3. **Documentation**: Update relevant documentation when changing APIs.
4. **PRs**: Include test results and coverage in PR descriptions.
5. **Branch naming**: Follow the branching conventions (`feat/*`, `fix/*`, `refactor/*`, `agent/*`).
6. **Commit messages**: Use Conventional Commits style.
7. **Feature flags**: Gate risky changes with Statsig.

### Common Tasks

- **Adding a new feature**:
  1. Create a branch: `feat/<short-desc>` off `main`.
  2. Start by understanding existing patterns in similar features.
  3. Implement behind a Statsig gate if user-visible or risky.
  4. Run `pnpm lint`, `pnpm typecheck`, `pnpm test` before pushing.
  5. Open a PR targeting `main` (do not merge yourself).

- **Fixing bugs**:
  1. Create a branch: `fix/<short-desc>` off `main`.
  2. Reproduce the issue first, add a failing test, then fix.
  3. Run `pnpm lint`, `pnpm typecheck`, `pnpm test` before pushing.
  4. Open a PR targeting `main` (do not merge yourself).

- **Refactoring**:
  1. Create a branch: `refactor/<area>-<short-desc>` off `main`.
  2. Ensure tests pass before and after, refactor in small steps.
  3. Run `pnpm lint`, `pnpm typecheck`, `pnpm test` before pushing.
  4. Open a PR targeting `main` (do not merge yourself).

- **Performance**:
  1. Profile before optimizing, focus on user-perceived performance.
  2. Add performance tests/benchmarks if applicable.
  3. Follow the same branch/PR flow as above.

### Swift Missing-File Rule

If the compiler reports that a referenced Swift file or type cannot be found, assume the reference is correct and the project setup needs to be updated. Follow these steps in order:

1. Ask the user to create the missing file and provide its complete contents.
2. If the file already exists, instruct the user to add it to the correct Xcode target/group.
3. As a last resort, resolve import, module, or path configuration issues.

Never “fix” this by swapping to legacy classes (for example `DashboardOld.swift`), commenting out the new feature, or reverting without explicit user approval. If you genuinely believe reverting is the only option, ask the user first.

## Change Management Discipline (formerly `.windsurf/rules/ios-rules.md`)

- Treat the current project files, build settings, and dependency graph as the single source of truth; never resurrect deleted code or alternate implementations without explicit direction.
- Before creating a new file/module/component, verify that an equivalent does not already exist. Prefer incremental updates over parallel versions, and ensure new code is fully wired into the runtime flow (routes, DI, targets, etc.).
- Keep a single active implementation per feature. If you replace a screen or service, update every call site and clearly mark any deprecated code so it is unused.
- Respect task scope: when asked to adjust a label/metric/endpoint, change only what is required to fulfill that request. Avoid opportunistic refactors or renames unless mandatory for the fix.
- Favor minimal diffs. Touch the fewest files/lines necessary and avoid unrelated formatting churn. Document in explanations which files changed, how they are used, and whether any previous files became obsolete.
- On Xcode projects, honor target membership: ensure new files are added to the correct targets, avoid reintroducing files that the project no longer references, and never leave “floating” alternative implementations disconnected from the app.

## Vendor Adapter Rule (Platform Boundary)

NEVER call third-party vendor SDKs/APIs directly from product/domain/UI code.
All external services (feature flags, analytics, email/notifications, payments, auth, logging, etc.) MUST be accessed only through our internal Platform Ports (protocol/interface) with vendor-specific Adapters.

### Requirements

- Product/Domain/UI layers import only Platform modules (ports + types).
- Vendor SDK imports are allowed only inside adapters.
- Ports define stable app-level IDs/schemas (event names, flag keys, template IDs).
- Swapping vendors must require changes only in adapters + DI wiring, not call sites.
- New vendor integration = add adapter, do not add new direct calls.

### Example

- ✅ `Analytics.track(AppEvent.signup_completed)`
- ❌ `posthog.capture("signup_completed")` in product code

## Security Considerations

### Secrets Management

- Never commit secrets or API keys
- Use `.xcconfig` files for iOS configuration (not in git)
- Use environment variables for web configuration
- All secrets are stored in GitHub Secrets for CI/CD

### Code Security

- Validate all user inputs
- Use parameterized queries for database operations
- Follow OWASP guidelines for web security
- Enable all iOS security features (ATS, code signing, etc.)

## Getting Help

### Resources

- iOS: Apple Developer Documentation, SwiftUI tutorials
- Web: Next.js docs, React docs, Tailwind CSS docs
- Both: Supabase docs, Clerk docs

### Debugging

- iOS: Use Xcode debugger and Instruments
- Web: Chrome DevTools, React Developer Tools
- Both: Check Supabase logs for backend issues

### Performance

- iOS: Profile with Instruments, optimize Core Data queries
- Web: Use Lighthouse, optimize bundle size
- Both: Monitor Supabase query performance

---

## Quick Reference for Agents

### Critical Rules (NEVER VIOLATE)

1. ❌ **NEVER push directly to `main`**
2. ❌ **NEVER merge PRs into `main`**
3. ❌ **NEVER use npm or yarn** (always use `pnpm`)
4. ❌ **NEVER bypass feature gates** for risky/user-facing changes
5. ❌ **NEVER change branch protection or CI configuration** without explicit request
6. ❌ **NEVER relax security or quality gates**

### Always Do

1. ✅ Work on short-lived branches off `main` (`feat/*`, `fix/*`, `refactor/*`, `agent/*`)
2. ✅ Run `pnpm lint`, `pnpm typecheck`, `pnpm test` before declaring work complete
3. ✅ Use Conventional Commits style (`feat:`, `fix:`, `refactor:`, etc.)
4. ✅ Gate risky changes with Statsig feature flags
5. ✅ Open PRs targeting `main` for human review (do not merge yourself)
6. ✅ Keep PRs small and focused
7. ✅ Use root-level `pnpm` scripts that leverage Turborepo
8. ✅ Respect existing code patterns and architecture

### Workflow Summary

```
1. Create branch: feat/<short-desc> (or fix/*, refactor/*, agent/*)
2. Make changes (commit frequently)
3. Run validation: pnpm lint && pnpm typecheck && pnpm test
4. Push to branch
5. Open PR targeting main
6. Wait for human review and CI to pass
7. Human merges PR (you do not merge)
```

### Package Manager Commands

```bash
# From repository root (always):
pnpm install            # Install dependencies
pnpm lint               # Lint all packages
pnpm typecheck          # Type-check all packages
pnpm test               # Run all tests
pnpm test:ci            # Run all tests in CI mode
pnpm build              # Build all packages/apps

# For specific apps/packages:
pnpm --filter apps/web lint
pnpm --filter packages/backend test
```

### CI/CD Workflows

- **`.github/workflows/ci.yml`**: Runs on PRs to `main` (required checks: `js` job, optional `ios` job)
- **`.github/workflows/deploy.yml`**: Runs on pushes to `main` (deploys web app to Vercel, optional iOS beta)

### Branch Protection

- `main` is protected: no direct pushes, PRs required, CI must pass, human review required

---

Remember: When in doubt, follow the existing patterns in the codebase. Consistency is more important than perfection.

**Agents propose; humans dispose. `main` only contains human-reviewed, CI-passing code.**
