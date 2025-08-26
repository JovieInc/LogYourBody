# LogYourBody Codebase Guidelines

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
- `CLAUDE.md` - iOS-specific AI assistant context

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
- Always check `CLAUDE.md` in the iOS directory for iOS-specific context
- Reference this `AGENTS.md` for general repository guidelines
- Update context files when making significant architectural changes

### Best Practices
1. **Exploration**: Use grep/glob tools to understand code structure before making changes
2. **Validation**: Always run lint and tests before committing
3. **Documentation**: Update relevant documentation when changing APIs
4. **Commits**: Write clear, concise commit messages following conventional commits
5. **PRs**: Include test results and coverage in PR descriptions

### Common Tasks
- **Adding a new feature**: Start by understanding existing patterns in similar features
- **Fixing bugs**: Reproduce the issue first, add a failing test, then fix
- **Refactoring**: Ensure tests pass before and after, refactor in small steps
- **Performance**: Profile before optimizing, focus on user-perceived performance

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