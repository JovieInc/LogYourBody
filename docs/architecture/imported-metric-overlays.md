# Imported metric overlays (LYB-243)

`MetricCorrectionService` exposes `exclude(_:)`, `correct(_:to:)`, and
`undo(_:)` for imported readings. Mutations require the default-off
`imported_metric_corrections` gate and an authenticated account session. Undo
remains available when the gate is disabled. This slice adds no controls or
marker design.

`BodyMetrics.originalWeight` and `originalBodyFatPercentage` remain the original
stored/wire values. `weight` and `bodyFatPercentage` resolve the optional
`correctedValue` overlay (kg and percentage); nil patch fields retain previous
corrections. Corrected fields are attributed to manual entry, without changing
imported provenance or methods. `isExcluded` is retained in reading fetches and
weight/body-fat history payloads, while calculations, chart samples and current
metric selection ignore it. Exclusion is separate from deletion and hiding.

The service reuses LYB-162's `PhotoMetricsUpdateResult` receipt (`metrics`,
`previousMetric`, `createdNewEntry`). Undo restores the exact previous overlay,
including an earlier correction or exclusion. Imported measurements, metadata,
photos and linked DEXA reports remain untouched. Sync timestamps advance so the
undo propagates. A stale receipt, deleted/foreign row, pending edit, expired
account session or failed save cannot overwrite another state.

Core Data V7 adds a default-false Boolean and an optional JSON string to the
retained V6 schema. V1–V6 stay byte-identical and bundled for inferred lightweight
migration. Migration tests create populated V4, V5 and V6 SQLite stores, open
them with V7, retain original measurements, workout reconciliation and dated
outcomes where present, check overlay defaults, and verify values after reopening.

Cloud persistence uses the existing first-party Neon sync API, not Supabase.
`20261025140000_imported_metric_overlays.sql` adds `is_excluded` and
`corrected_value` to `body_metrics`. Native push/pull retains original fields and
sends overlays separately. Older clients may omit the new keys without clearing
existing overlays; explicit false/null clears them. Deploy the additive schema
and API before enabling the native mutation gate.

`MetricCorrectionTests`, `MetricChartDataHelperTests` and
`CoreDataModelMigrationTests` cover undo, originals, DEXA payload retention,
calculations, chart cache changes, migration and failure paths. The required JS
suite includes `metric-correction-boundary.test.ts`, which prohibits health-store
writers in the correction service and its persistence/cloud-sync dependencies,
and permits persistence assignments only to overlays and sync bookkeeping.
Native XCTest execution and coverage must come from the real macOS runner;
Linux lint and JS contracts do not replace that evidence.
