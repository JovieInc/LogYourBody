# Supabase Configuration

This directory contains the unified Supabase configuration for both the iOS and web applications.

## Structure

```
supabase/
├── config.toml          # Supabase configuration
├── migrations/          # Database migrations (shared by all apps)
├── functions/           # Edge functions
├── deploy.sh           # Deployment script
└── .temp/              # Temporary files (git ignored)
```

## Setup

1. **Install Supabase CLI**:

   ```bash
   brew install supabase/tap/supabase
   ```

2. **Link your project**:

   ```bash
   cd supabase
   supabase link --project-ref <your-project-ref>
   ```

3. **Deploy**:
   ```bash
   ./deploy.sh
   ```

## Important Notes

- Both iOS and web apps share the same database schema
- The storage bucket is named `photos` (not `progress-photos`)
- `supabase/migrations/` is the only canonical migration tree. App-local migration directories must not be reintroduced.
- Edge functions from individual apps are copied during deployment

## Migration Naming Convention

Use the format: `YYYYMMDDHHMMSS_description.sql`

Example: `20250706120000_add_photo_fields.sql`

Create migrations from the repository root:

```bash
pnpm db:migrate "add photo fields"
```

## Storage Configuration

The `photos` bucket is configured with:

- Private access
- 50MB file size limit
- Allowed types: JPEG, PNG, HEIC, HEIF, WebP
- Storage RLS policies ensure users can only access their own photos. Clients should use stored object paths plus signed URLs, not public object URLs.

## Unified Weight Model

- Both iOS and web now read and write weight data via the `body_metrics` table.
- Historical data from the legacy `weight_logs` table is backfilled into `body_metrics` by the `20250705000000_backfill_weight_logs_into_body_metrics.sql` migration.
- The `weight_logs` identifier is preserved as a read-only compatibility view over `body_metrics` by the `20250705000001_convert_weight_logs_to_view.sql` migration. New writes must target `body_metrics`, not `weight_logs`.
- `body_metrics.date` stores the precise timestamp for ordering and sync conflict handling.
- `body_metrics.local_date` stores the user-device calendar day (`YYYY-MM-DD`) for stable day buckets across timezone changes.

**Canonical source of truth for weight:** `public.body_metrics`.

## Body Metric Source Provenance

- `body_metrics.data_source` stores canonical `BodyMetricSource` values: `manual`, `healthkit`, `smart_scale`, `bodyspec_dexa`, `caliper`, and `photo`.
- `body_metrics.source_metadata` stores compact pointer-style provenance such as HealthKit sample IDs, quantity types, source bundle/device identifiers, BodySpec result IDs, scanner/location IDs, or legacy source labels.
- Do not store raw vendor payloads, access tokens, refresh tokens, or unnecessary personal data in source metadata.
