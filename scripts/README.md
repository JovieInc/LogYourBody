# Scripts Directory

This directory contains essential CI/CD and configuration scripts for the LogYourBody project.

## Directory Structure

```
scripts/
├── web/                    # Web app essential scripts
│   ├── pre-push-check.sh   # Git pre-push checks
│   └── create-migration.sh # Neon migration creator
├── neon/                   # Neon migration layout checks
└── ios/                    # iOS build and release helpers
```

## Web Scripts

The tracked web scripts cover production migrations and build support. Keep schema
changes in `apps/web/db/migrations` and apply them through the checked-in Neon
migration runner.

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
