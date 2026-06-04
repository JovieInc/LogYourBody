# Scripts Directory

This directory contains essential CI/CD and configuration scripts for the LogYourBody project.

## Directory Structure

```
scripts/
├── web/                    # Web app essential scripts
│   ├── pre-push-check.sh   # Git pre-push checks
│   └── create-migration.sh # Database migration creator
├── add-clerk-env-secrets.sh    # Add Clerk secrets to GitHub environments
├── add-clerk-secrets.sh        # Add Clerk secrets to repository
├── check-env-secrets.sh        # Check environment secrets configuration
└── test-clerk-config.js        # Test Clerk configuration locally
```

## Web Scripts

The `apps/web/scripts/` directory has been gitignored to prevent CodeQL warnings from development scripts. Only essential scripts remain:

- `seed-database.ts` - Database seeding
- `test-seeded-users.ts` - Test seeded data

All other scripts (avatar generators, test scripts, etc.) are ignored by git but remain available for local development.

## Usage

### Clerk Configuration

```bash
# Check current environment secrets
./scripts/check-env-secrets.sh

# Add secrets to an environment
./scripts/add-clerk-env-secrets.sh development
```

### Web Development

```bash
# Run pre-push checks
cd apps/web && pnpm run check

# Create a database migration
cd apps/web && pnpm run db:migrate
```
