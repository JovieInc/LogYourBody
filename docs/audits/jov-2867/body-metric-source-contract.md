# JOV-2867 BodyMetricSource Storage and Sync Contract

## Scope

This issue defines the provenance contract that future body metric imports must use before expanding HealthKit, BodySpec/DEXA, smart-scale, caliper, or photo-derived data.

## Canonical Source Values

`BodyMetricSource` is stored in `body_metrics.data_source` and in the iOS local `CachedBodyMetrics.dataSource` field as one of:

- `manual`
- `healthkit`
- `smart_scale`
- `bodyspec_dexa`
- `caliper`
- `photo`

Legacy labels are normalized on read/write. Examples: `Manual` becomes `manual`, `HealthKit` becomes `healthkit`, `partner:bodyspec` becomes `bodyspec_dexa`, and `Photo Import` becomes `photo`.

## Metadata

Compact provenance is stored as JSON in `body_metrics.source_metadata` and as `CachedBodyMetrics.sourceMetadataJSON` on iOS. The metadata shape is pointer-style only:

- vendor/source identifiers
- source bundle identifier
- device manufacturer/model/id
- HealthKit sample ID, quantity type, and paired body-fat sample ID when available
- external importer/result IDs
- scanner/location identifiers
- imported timestamp
- legacy source label for unknown historical rows

Do not store raw vendor payloads, access tokens, refresh tokens, or unnecessary personal data in `source_metadata`.

## Migration

The additive Supabase migration is:

- `supabase/migrations/20260607043000_define_body_metric_source.sql`

It adds `source_metadata`, normalizes legacy `data_source` values, defaults future rows to `manual`, and constrains future writes to the six canonical values.

## iOS Mapping

- `BodyMetrics` now normalizes `dataSource` at construction and decode time.
- `CoreDataManager.saveBodyMetrics` persists canonical `dataSource` and optional metadata JSON.
- `CoreDataManager.updateOrCreateBodyMetric` maps `data_source` and `source_metadata` from Supabase payloads.
- `RealtimeSyncManager.syncBodyMetricsBatch` sends both fields during local-to-remote sync.
- HealthKit body metric rows use `healthkit`; raw sample metadata remains in `HKRawSample`.
- BodySpec-created body metric rows use `bodyspec_dexa` and include scan/result metadata.
- Photo-only metric rows use `photo`.

## Deferred

This does not add importer UI, smart-scale import, caliper entry, HealthKit sample-to-metric reconciliation, or DEXA conflict handling. Those remain separate roadmap issues.

## Done When

Future metric import code can declare source provenance using the stable source values and optional metadata without changing product/UI call sites or rewriting the sync layer.
