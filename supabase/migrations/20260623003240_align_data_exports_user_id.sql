-- Align temporary export ownership with Clerk text user ids.
-- The table is only accessed by Edge Functions with the service role, but the
-- stored owner id must match the rest of the canonical Clerk-backed schema.

DO $$
DECLARE
    fk_name TEXT;
BEGIN
    IF to_regclass('public.data_exports') IS NULL THEN
        RETURN;
    END IF;

    SELECT con.conname
    INTO fk_name
    FROM pg_constraint con
    JOIN pg_attribute attr
      ON attr.attrelid = con.conrelid
     AND attr.attnum = ANY(con.conkey)
    WHERE con.conrelid = 'public.data_exports'::regclass
      AND con.contype = 'f'
      AND attr.attname = 'user_id'
    LIMIT 1;

    IF fk_name IS NOT NULL THEN
        EXECUTE format('ALTER TABLE public.data_exports DROP CONSTRAINT %I', fk_name);
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'data_exports'
          AND column_name = 'user_id'
          AND data_type <> 'text'
    ) THEN
        ALTER TABLE public.data_exports
            ALTER COLUMN user_id TYPE TEXT USING user_id::text;
    END IF;

    ALTER TABLE public.data_exports
        ALTER COLUMN user_id SET NOT NULL;
END
$$;

ALTER TABLE IF EXISTS public.data_exports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Service role can manage exports" ON public.data_exports;

CREATE POLICY "Service role can manage exports" ON public.data_exports
    FOR ALL
    TO service_role
    USING (true)
    WITH CHECK (true);

COMMENT ON COLUMN public.data_exports.user_id IS
    'Clerk user id for the owner of the temporary export payload.';
