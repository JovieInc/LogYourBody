-- Convert legacy weight_logs table into a read-only compatibility view backed by body_metrics
-- This assumes the Clerk-safe migrations have already run and body_metrics is the canonical source.

DO $$
BEGIN
    -- Only drop if weight_logs is still a real table
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public'
          AND table_name = 'weight_logs'
    ) THEN
        DROP TABLE public.weight_logs CASCADE;
    END IF;
END
$$;

-- Create a view with the same shape as the old weight_logs table
CREATE OR REPLACE VIEW public.weight_logs AS
SELECT
    id,
    user_id,
    date AS logged_at,
    weight,
    weight_unit,
    notes,
    created_at,
    updated_at
FROM public.body_metrics;
