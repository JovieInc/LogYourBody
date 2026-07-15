# Scripts Directory

This directory contains essential CI/CD and configuration scripts for the LogYourBody project.

## Directory Structure

```
scripts/
├── web/                    # Web app essential scripts
│   ├── pre-push-check.sh   # Git pre-push checks
│   └── create-migration.sh # Root Supabase migration creator
├── supabase/               # Supabase schema checks
└── ios/                    # iOS build and release helpers
```

## Web Scripts

The `apps/web/scripts/` directory has been gitignored to prevent CodeQL warnings from development scripts. Only essential scripts remain:

- `seed-database.ts` - Database seeding
- `test-seeded-users.ts` - Test seeded data

All other scripts (avatar generators, test scripts, etc.) are ignored by git but remain available for local development.

## Usage

### Web Development

```bash
# Run pre-push checks
cd apps/web && pnpm run check

# Create a database migration
pnpm db:migrate "add user preferences"

# Verify migration ownership and optional schema drift
pnpm db:schema:check
```
