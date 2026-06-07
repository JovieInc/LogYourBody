-- Define stable body metric source provenance before expanding imports.
-- This migration is additive and normalizes existing legacy labels in place.

ALTER TABLE public.body_metrics
ADD COLUMN IF NOT EXISTS data_source TEXT DEFAULT 'manual',
ADD COLUMN IF NOT EXISTS source_metadata JSONB NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE public.body_metrics
ALTER COLUMN data_source SET DEFAULT 'manual';

ALTER TABLE public.body_metrics
ALTER COLUMN source_metadata SET DEFAULT '{}'::jsonb;

UPDATE public.body_metrics
SET source_metadata = '{}'::jsonb
WHERE source_metadata IS NULL OR jsonb_typeof(source_metadata) <> 'object';

WITH normalized AS (
    SELECT
        id,
        data_source AS original_data_source,
        regexp_replace(lower(trim(coalesce(data_source, ''))), '[ -]+', '_', 'g') AS source_key
    FROM public.body_metrics
),
resolved AS (
    SELECT
        id,
        original_data_source,
        source_key,
        CASE
            WHEN source_key IN ('', 'manual', 'user', 'user_entered', 'user_entry') THEN 'manual'
            WHEN source_key IN ('healthkit', 'health_kit', 'apple_health', 'apple_healthkit') THEN 'healthkit'
            WHEN source_key IN ('smart_scale', 'scale', 'bia_scale', 'body_scale', 'connected_scale') THEN 'smart_scale'
            WHEN source_key IN ('bodyspec_dexa', 'bodyspec', 'partner:bodyspec', 'partner_bodyspec', 'dexa', 'dxa')
                OR source_key LIKE '%bodyspec%' THEN 'bodyspec_dexa'
            WHEN source_key LIKE '%caliper%' OR source_key LIKE '%skinfold%' THEN 'caliper'
            WHEN source_key IN ('photo', 'photo_import', 'progress_photo') THEN 'photo'
            ELSE 'manual'
        END AS canonical_data_source
    FROM normalized
)
UPDATE public.body_metrics AS body_metrics
SET
    data_source = resolved.canonical_data_source,
    source_metadata = CASE
        WHEN resolved.canonical_data_source = 'manual'
            AND resolved.source_key NOT IN ('', 'manual', 'user', 'user_entered', 'user_entry')
            AND resolved.original_data_source IS NOT NULL
        THEN body_metrics.source_metadata || jsonb_build_object('legacy_data_source', resolved.original_data_source)
        ELSE body_metrics.source_metadata
    END
FROM resolved
WHERE body_metrics.id = resolved.id;

ALTER TABLE public.body_metrics
ALTER COLUMN data_source SET NOT NULL;

ALTER TABLE public.body_metrics
ALTER COLUMN source_metadata SET NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'body_metrics_data_source_allowed'
          AND conrelid = 'public.body_metrics'::regclass
    ) THEN
        ALTER TABLE public.body_metrics
        ADD CONSTRAINT body_metrics_data_source_allowed
        CHECK (
            data_source IN (
                'manual',
                'healthkit',
                'smart_scale',
                'bodyspec_dexa',
                'caliper',
                'photo'
            )
        ) NOT VALID;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'body_metrics_source_metadata_object'
          AND conrelid = 'public.body_metrics'::regclass
    ) THEN
        ALTER TABLE public.body_metrics
        ADD CONSTRAINT body_metrics_source_metadata_object
        CHECK (jsonb_typeof(source_metadata) = 'object') NOT VALID;
    END IF;
END
$$;

ALTER TABLE public.body_metrics VALIDATE CONSTRAINT body_metrics_data_source_allowed;
ALTER TABLE public.body_metrics VALIDATE CONSTRAINT body_metrics_source_metadata_object;

CREATE INDEX IF NOT EXISTS idx_body_metrics_data_source
ON public.body_metrics(data_source);

COMMENT ON COLUMN public.body_metrics.data_source IS
'Canonical BodyMetricSource: manual, healthkit, smart_scale, bodyspec_dexa, caliper, or photo.';

COMMENT ON COLUMN public.body_metrics.source_metadata IS
'Compact source provenance such as sample, external result, vendor, or device identifiers. Do not store raw vendor payloads or secrets.';
