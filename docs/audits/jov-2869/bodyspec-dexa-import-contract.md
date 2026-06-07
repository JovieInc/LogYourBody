# JOV-2869 BodySpec DEXA Import Contract

## Scope

BodySpec DEXA imports are additive body-composition events. They should enrich the timeline without replacing manual or HealthKit body metrics.

## Source Contract

Imported DEXA body metric rows must use:

- `data_source`: `bodyspec_dexa`
- `body_fat_method`: `DEXA (BodySpec)`
- `source_metadata.vendor`: `bodyspec`
- `source_metadata.source_name`: `BodySpec DEXA`
- `source_metadata.external_result_id`: BodySpec result ID
- `source_metadata.external_id`: BodySpec service ID when available
- scanner, location, and imported-at metadata when available

`dexa_results.external_source` remains `bodyspec` and links back to the imported body metric through `body_metrics_id`.

## Reconciliation

DEXA imports never overwrite manual or HealthKit body metrics. If a manual or HealthKit value exists on the same day, the DEXA importer creates a separate `bodyspec_dexa` row with its own timestamp and provenance.

Duplicate handling is deterministic:

- Skip an import when an existing body metric has the same `source_metadata.external_result_id`.
- Also skip legacy BodySpec rows with no metadata only when they are within 60 seconds of the scan timestamp.
- Do not skip unrelated same-day manual, HealthKit, or different BodySpec result rows.

## Done When

DEXA scans can enter the local timeline and Supabase sync as auditable, additive metric events with predictable duplicate handling.
