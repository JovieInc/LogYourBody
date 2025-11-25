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
├── packages/          # Shared packages
│   └── supabase/      # Shared Supabase client and types
├── .github/           # GitHub Actions workflows and configurations
└── docs/              # Project documentation
```

## Project Context

- Mission: help users monitor weight, body composition, and progress photos with HealthKit integration and Supabase-backed sync.
- Platforms: Native iOS app (SwiftUI, Swift 5.9+) and Next.js web app share Clerk-based authentication.
- Key stacks:
  - **Authentication**: Clerk SDK with browser-based OAuth for Apple Sign In.
  - **Design System**: iOS 26 Liquid Glass with graceful fallbacks.
  - **Data**: Core Data for local storage, Supabase for cloud sync, HealthKit for weight and step data.

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
When making web changes, run these commands from `apps/web/`:
```bash
# Install dependencies
pnpm install

# Type check
pnpm type-check

# Lint
pnpm lint

# Run tests
pnpm test

# Build
pnpm build
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

## CI/CD & Testing

### GitHub Actions
- **ios-rapid-loop.yml**: Fast feedback on iOS changes (runs on every push)
- **ios-confidence-loop.yml**: Comprehensive iOS testing (runs on PR/schedule)
- **ios-release-loop.yml**: Production deployment (manual trigger)
- **security-scan.yml**: Weekly security scanning

### Test Coverage Requirements
- iOS: Minimum 70% code coverage
- Web: Minimum 80% code coverage
- All new features must include tests

## Migration Notes

### Current Migrations
1. **iOS Code Signing**: Moving to Fastlane Match for certificate management
2. **CI Performance**: Migrating to macOS-14 runners for better performance
3. **Design System**: Updating to iOS 26 Liquid Glass design patterns

## Working with AI Agents

### Context Files
- Reference this `AGENTS.md` for *all* AI-assistant guidance. Other docs (e.g., `CLAUDE.md`, `.windsurf/rules/ios-rules.md`) now simply point back here.
- Update this file whenever process guidance changes.

### Best Practices
1. **Exploration**: Use grep/glob tools to understand code structure before making changes
2. **Validation**: Always run lint and tests before committing
3. **Documentation**: Update relevant documentation when changing APIs
5. **PRs**: Include test results and coverage in PR descriptions

### Common Tasks
- **Adding a new feature**: Start by understanding existing patterns in similar features
- **Fixing bugs**: Reproduce the issue first, add a failing test, then fix
- **Refactoring**: Ensure tests pass before and after, refactor in small steps
- **Performance**: Profile before optimizing, focus on user-perceived performance

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

Remember: When in doubt, follow the existing patterns in the codebase. Consistency is more important than perfection.