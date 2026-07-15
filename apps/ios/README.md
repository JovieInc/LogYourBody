# LogYourBody iOS App

Native iOS app for LogYourBody - a fitness tracking application that helps users monitor weight, body composition, and progress photos.

## Documentation

**Complete documentation is available in the [docs/](./docs/) directory:**

- [Setup Guides](./docs/setup/) - Environment setup, dependencies, and configuration
- [Development Guides](./docs/development/) - Workflows, testing, and troubleshooting
- [Architecture Docs](./docs/architecture/) - Design system, project structure, and technical plans

## Quick Start

1. **Configure Environment** - See [docs/setup/CONFIGURATION.md](./docs/setup/CONFIGURATION.md)
2. **Configure shared auth** - See [shared identity architecture](../../docs/auth/shared-identity-architecture.md)
3. **Understand CI/CD** - See [docs/development/CI_README.md](./docs/development/CI_README.md)

## Tech Stack

- **SwiftUI** - iOS 26 Liquid Glass design system
- **Jovie Better Auth** - Shared phone-number identity through Supabase OIDC
- **Supabase** - Product sessions, backend, and cloud sync
- **Core Data** - Local data persistence
- **HealthKit** - Weight and step data integration

## Features

- Fast SMS authentication with a shared Jovie identity
- Weight logging and tracking
- Progress photo management
- HealthKit integration
- Body composition metrics
- Cloud sync with Supabase
- iOS widgets

## CI/CD

This project uses a three-loop CI/CD system:

- **Rapid Loop** - Fast checks on every commit
- **Confidence Loop** - Comprehensive tests for validated builds
- **Release Loop** - Automated TestFlight and App Store deployment

See [docs/development/CI_README.md](./docs/development/CI_README.md) for details.
