-- Backfill body_metrics from weight_logs so both iOS and web use a unified table for weight
-- This migration is idempotent and safe to run multiple times.

DO $$
BEGIN
    -- Only run if the weight_logs table exists
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name = 'weight_logs'
    ) THEN
        INSERT INTO public.body_metrics (
            id,
            user_id,
            date,
            weight,
            weight_unit,
            notes,
            created_at,
            updated_at
        )
        SELECT
            wl.id,
            wl.user_id,
            wl.logged_at,
            wl.weight,
            wl.weight_unit,
            wl.notes,
            wl.created_at,
            wl.updated_at
        FROM public.weight_logs AS wl
        ON CONFLICT (id) DO NOTHING;
    END IF;
END
$$;
