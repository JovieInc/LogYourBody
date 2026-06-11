-- Restore body_metrics CHECK constraints dropped by the Clerk-safe table swap.
-- Existing impossible values are preserved in source_metadata before being nulled,
-- so constraint validation can complete without silently losing the original input.

WITH candidate_rows AS (
    SELECT
        id,
        weight IS NOT NULL
            AND NOT COALESCE(
                (weight_unit = 'kg' AND weight BETWEEN 11.3 AND 453.6)
                OR (weight_unit = 'lbs' AND weight BETWEEN 25 AND 1000),
                false
            ) AS invalid_weight,
        body_fat_percentage IS NOT NULL
            AND NOT (body_fat_percentage BETWEEN 0 AND 70) AS invalid_body_fat_percentage,
        muscle_mass IS NOT NULL
            AND weight IS NOT NULL
            AND muscle_mass >= weight AS invalid_muscle_mass
    FROM public.body_metrics
),
invalid_rows AS (
    SELECT *
    FROM candidate_rows
    WHERE invalid_weight
       OR invalid_body_fat_percentage
       OR invalid_muscle_mass
)
UPDATE public.body_metrics AS body_metrics
SET
    source_metadata = coalesce(body_metrics.source_metadata, '{}'::jsonb)
        || jsonb_build_object(
            'pre_constraint_invalid_values',
            jsonb_strip_nulls(
                jsonb_build_object(
                    'weight', CASE WHEN invalid_rows.invalid_weight THEN body_metrics.weight END,
                    'weight_unit', CASE WHEN invalid_rows.invalid_weight THEN body_metrics.weight_unit END,
                    'body_fat_percentage', CASE
                        WHEN invalid_rows.invalid_body_fat_percentage THEN body_metrics.body_fat_percentage
                    END,
                    'muscle_mass', CASE WHEN invalid_rows.invalid_muscle_mass THEN body_metrics.muscle_mass END
                )
            ),
            'pre_constraint_cleaned_at',
            now()
        ),
    weight = CASE WHEN invalid_rows.invalid_weight THEN NULL ELSE body_metrics.weight END,
    body_fat_percentage = CASE
        WHEN invalid_rows.invalid_body_fat_percentage THEN NULL
        ELSE body_metrics.body_fat_percentage
    END,
    muscle_mass = CASE
        WHEN invalid_rows.invalid_muscle_mass THEN NULL
        ELSE body_metrics.muscle_mass
    END
FROM invalid_rows
WHERE body_metrics.id = invalid_rows.id;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'weight_range_check'
          AND conrelid = 'public.body_metrics'::regclass
    ) THEN
        ALTER TABLE public.body_metrics
        ADD CONSTRAINT weight_range_check
        CHECK (
            (weight_unit = 'kg' AND weight BETWEEN 11.3 AND 453.6)
            OR (weight_unit = 'lbs' AND weight BETWEEN 25 AND 1000)
            OR weight IS NULL
        ) NOT VALID;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'body_fat_percentage_range_check'
          AND conrelid = 'public.body_metrics'::regclass
    ) THEN
        ALTER TABLE public.body_metrics
        ADD CONSTRAINT body_fat_percentage_range_check
        CHECK (body_fat_percentage BETWEEN 0 AND 70 OR body_fat_percentage IS NULL) NOT VALID;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conname = 'muscle_mass_range_check'
          AND conrelid = 'public.body_metrics'::regclass
    ) THEN
        ALTER TABLE public.body_metrics
        ADD CONSTRAINT muscle_mass_range_check
        CHECK (muscle_mass < weight OR muscle_mass IS NULL) NOT VALID;
    END IF;
END
$$;

ALTER TABLE public.body_metrics VALIDATE CONSTRAINT weight_range_check;
ALTER TABLE public.body_metrics VALIDATE CONSTRAINT body_fat_percentage_range_check;
ALTER TABLE public.body_metrics VALIDATE CONSTRAINT muscle_mass_range_check;

COMMENT ON CONSTRAINT weight_range_check ON public.body_metrics IS
'Ensures weight is between 25lbs (11.3kg) and 1000lbs (453.6kg).';

COMMENT ON CONSTRAINT body_fat_percentage_range_check ON public.body_metrics IS
'Ensures body fat percentage is between 0% and 70%.';

COMMENT ON CONSTRAINT muscle_mass_range_check ON public.body_metrics IS
'Ensures muscle mass is less than total body weight.';
