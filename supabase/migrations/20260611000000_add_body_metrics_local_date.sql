-- Store the user's logged calendar day separately from the precise timestamp.
-- The timestamp remains the ordering/source-of-truth instant; local_date is used
-- for day buckets that must not drift when the device timezone changes.

ALTER TABLE public.body_metrics
ADD COLUMN IF NOT EXISTS local_date DATE;

UPDATE public.body_metrics
SET local_date = (date AT TIME ZONE 'UTC')::date
WHERE local_date IS NULL
  AND date IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_body_metrics_user_local_date
ON public.body_metrics(user_id, local_date DESC)
WHERE local_date IS NOT NULL;

COMMENT ON COLUMN public.body_metrics.local_date IS
'Calendar day on the user device when the metric was logged, formatted as a DATE for stable local-day grouping.';
