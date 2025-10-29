# LogYourBody iOS Documentation

This directory contains all documentation for the LogYourBody iOS app, organized by category.

## Directory Structure

### [Setup](./setup/)
Environment configuration, dependencies, and initial setup guides.

- [CLERK_SETUP.md](./setup/CLERK_SETUP.md) - Clerk authentication setup
- [CONFIGURATION.md](./setup/CONFIGURATION.md) - App configuration
- [GITHUB_SECRETS_SETUP.md](./setup/GITHUB_SECRETS_SETUP.md) - CI/CD secrets configuration
- [MATCH_SETUP_INSTRUCTIONS.md](./setup/MATCH_SETUP_INSTRUCTIONS.md) - Code signing with fastlane match
- [match_usage.md](./setup/match_usage.md) - Match usage guide
- [RLS_SETUP_GUIDE.md](./setup/RLS_SETUP_GUIDE.md) - Row Level Security setup for Supabase
- [SUPABASE_SETUP.md](./setup/SUPABASE_SETUP.md) - Supabase backend setup
- [SWIFTLINT_SETUP.md](./setup/SWIFTLINT_SETUP.md) - SwiftLint configuration
- [WIDGET_SETUP.md](./setup/WIDGET_SETUP.md) - iOS widget setup

### [Development](./development/)
Development workflows, testing, debugging, and optimization guides.

- [CI_README.md](./development/CI_README.md) - Continuous Integration workflows
- [CLAUDE.md](./development/CLAUDE.md) - AI-assisted development guide
- [FIX_ONBOARDING_CRASH.md](./development/FIX_ONBOARDING_CRASH.md) - Onboarding troubleshooting
- [LOADING_OPTIMIZATIONS.md](./development/LOADING_OPTIMIZATIONS.md) - Performance optimizations
- [SYNC_TROUBLESHOOTING.md](./development/SYNC_TROUBLESHOOTING.md) - Data sync debugging

### [Architecture](./architecture/)
System architecture, design patterns, and technical planning.

- [PROJECT_STRUCTURE.md](./architecture/PROJECT_STRUCTURE.md) - Project organization
- [AtomicDesignGuide.md](./architecture/AtomicDesignGuide.md) - Atomic Design System guide
- [README.md](./architecture/README.md) - Design system overview
- [APP_STORE_LAUNCH_PLAN.md](./architecture/APP_STORE_LAUNCH_PLAN.md) - Launch strategy
- [BULK_PHOTO_IMPORT_PLAN.md](./architecture/BULK_PHOTO_IMPORT_PLAN.md) - Photo import feature
- [ATOMIC_AUDIT_REPORT.md](./architecture/ATOMIC_AUDIT_REPORT.md) - Design system audit
- [ATOMIC_CLEANUP_STATUS.md](./architecture/ATOMIC_CLEANUP_STATUS.md) - Cleanup status
- [ATOMIC_CLEANUP_FINAL_STATUS.md](./architecture/ATOMIC_CLEANUP_FINAL_STATUS.md) - Final cleanup report
- [BUILD_ERROR_ANALYSIS.md](./architecture/BUILD_ERROR_ANALYSIS.md) - Build error analysis
- [DEDUPLICATION_SUMMARY.md](./architecture/DEDUPLICATION_SUMMARY.md) - Code deduplication summary

### [Archive](./archive/)
Historical documentation, old troubleshooting guides, and deprecated instructions.

- Previous Xcode integration guides
- Historical cleanup reports
- Legacy implementation status documents

## Getting Started

New to the project? Start here:

1. [CONFIGURATION.md](./setup/CONFIGURATION.md) - Set up your development environment
2. [CLERK_SETUP.md](./setup/CLERK_SETUP.md) - Configure authentication
3. [SUPABASE_SETUP.md](./setup/SUPABASE_SETUP.md) - Set up the backend
4. [CI_README.md](./development/CI_README.md) - Understand the CI/CD pipeline
5. [PROJECT_STRUCTURE.md](./architecture/PROJECT_STRUCTURE.md) - Learn the codebase structure

## Contributing

When adding new documentation:
- Place setup/configuration docs in `setup/`
- Place development workflows/debugging docs in `development/`
- Place architecture decisions/designs in `architecture/`
- Move outdated docs to `archive/` rather than deleting them

Keep documentation up-to-date and consolidate related guides when possible.
