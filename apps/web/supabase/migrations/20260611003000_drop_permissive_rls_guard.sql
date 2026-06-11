-- Guard against permissive Clerk transition RLS policies being present on a
-- freshly migrated or restored Supabase project.

-- Remove old application-layer-only policies from active tables.
DROP POLICY IF EXISTS "Authenticated users can manage profiles" ON public.profiles;
DROP POLICY IF EXISTS "Authenticated users can manage body_metrics" ON public.body_metrics;
DROP POLICY IF EXISTS "Authenticated users can manage daily_metrics" ON public.daily_metrics;
DROP POLICY IF EXISTS "Authenticated users can manage progress_photos" ON public.progress_photos;
DROP POLICY IF EXISTS "Authenticated users can manage email_subscriptions" ON public.email_subscriptions;

-- Replace active-table policies with Clerk user-scoped policies.
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.body_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.daily_metrics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.progress_photos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.email_subscriptions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON public.profiles;

CREATE POLICY "Users can view own profile" ON public.profiles
    FOR SELECT TO authenticated
    USING (id = auth.jwt()->>'sub');

CREATE POLICY "Users can update own profile" ON public.profiles
    FOR UPDATE TO authenticated
    USING (id = auth.jwt()->>'sub')
    WITH CHECK (id = auth.jwt()->>'sub');

CREATE POLICY "Users can insert own profile" ON public.profiles
    FOR INSERT TO authenticated
    WITH CHECK (id = auth.jwt()->>'sub');

DROP POLICY IF EXISTS "Users can view own body metrics" ON public.body_metrics;
DROP POLICY IF EXISTS "Users can insert own body metrics" ON public.body_metrics;
DROP POLICY IF EXISTS "Users can update own body metrics" ON public.body_metrics;
DROP POLICY IF EXISTS "Users can delete own body metrics" ON public.body_metrics;

CREATE POLICY "Users can view own body metrics" ON public.body_metrics
    FOR SELECT TO authenticated
    USING (user_id = auth.jwt()->>'sub');

CREATE POLICY "Users can insert own body metrics" ON public.body_metrics
    FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.jwt()->>'sub');

CREATE POLICY "Users can update own body metrics" ON public.body_metrics
    FOR UPDATE TO authenticated
    USING (user_id = auth.jwt()->>'sub')
    WITH CHECK (user_id = auth.jwt()->>'sub');

CREATE POLICY "Users can delete own body metrics" ON public.body_metrics
    FOR DELETE TO authenticated
    USING (user_id = auth.jwt()->>'sub');

DROP POLICY IF EXISTS "Users can view own daily metrics" ON public.daily_metrics;
DROP POLICY IF EXISTS "Users can insert own daily metrics" ON public.daily_metrics;
DROP POLICY IF EXISTS "Users can update own daily metrics" ON public.daily_metrics;
DROP POLICY IF EXISTS "Users can delete own daily metrics" ON public.daily_metrics;

CREATE POLICY "Users can view own daily metrics" ON public.daily_metrics
    FOR SELECT TO authenticated
    USING (user_id = auth.jwt()->>'sub');

CREATE POLICY "Users can insert own daily metrics" ON public.daily_metrics
    FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.jwt()->>'sub');

CREATE POLICY "Users can update own daily metrics" ON public.daily_metrics
    FOR UPDATE TO authenticated
    USING (user_id = auth.jwt()->>'sub')
    WITH CHECK (user_id = auth.jwt()->>'sub');

CREATE POLICY "Users can delete own daily metrics" ON public.daily_metrics
    FOR DELETE TO authenticated
    USING (user_id = auth.jwt()->>'sub');

DROP POLICY IF EXISTS "Users can view own progress photos" ON public.progress_photos;
DROP POLICY IF EXISTS "Users can insert own progress photos" ON public.progress_photos;
DROP POLICY IF EXISTS "Users can update own progress photos" ON public.progress_photos;
DROP POLICY IF EXISTS "Users can delete own progress photos" ON public.progress_photos;

CREATE POLICY "Users can view own progress photos" ON public.progress_photos
    FOR SELECT TO authenticated
    USING (user_id = auth.jwt()->>'sub');

CREATE POLICY "Users can insert own progress photos" ON public.progress_photos
    FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.jwt()->>'sub');

CREATE POLICY "Users can update own progress photos" ON public.progress_photos
    FOR UPDATE TO authenticated
    USING (user_id = auth.jwt()->>'sub')
    WITH CHECK (user_id = auth.jwt()->>'sub');

CREATE POLICY "Users can delete own progress photos" ON public.progress_photos
    FOR DELETE TO authenticated
    USING (user_id = auth.jwt()->>'sub');

DROP POLICY IF EXISTS "Users can view own email subscriptions" ON public.email_subscriptions;
DROP POLICY IF EXISTS "Users can update own email subscriptions" ON public.email_subscriptions;
DROP POLICY IF EXISTS "Users can insert own email subscriptions" ON public.email_subscriptions;

CREATE POLICY "Users can view own email subscriptions" ON public.email_subscriptions
    FOR SELECT TO authenticated
    USING (user_id = auth.jwt()->>'sub');

CREATE POLICY "Users can update own email subscriptions" ON public.email_subscriptions
    FOR UPDATE TO authenticated
    USING (user_id = auth.jwt()->>'sub')
    WITH CHECK (user_id = auth.jwt()->>'sub');

CREATE POLICY "Users can insert own email subscriptions" ON public.email_subscriptions
    FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.jwt()->>'sub');

-- The compatibility weight_logs object is a view in current migrations. If a
-- restored project still has it as a table, remove the permissive policy and
-- replace it with user-scoped access.
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public'
          AND c.relname = 'weight_logs'
          AND c.relkind IN ('r', 'p')
    ) THEN
        ALTER TABLE public.weight_logs ENABLE ROW LEVEL SECURITY;
        DROP POLICY IF EXISTS "Authenticated users can manage weight_logs" ON public.weight_logs;
        DROP POLICY IF EXISTS "Users can view own weight logs" ON public.weight_logs;
        DROP POLICY IF EXISTS "Users can insert own weight logs" ON public.weight_logs;
        DROP POLICY IF EXISTS "Users can update own weight logs" ON public.weight_logs;
        DROP POLICY IF EXISTS "Users can delete own weight logs" ON public.weight_logs;

        CREATE POLICY "Users can view own weight logs" ON public.weight_logs
            FOR SELECT TO authenticated
            USING (user_id = auth.jwt()->>'sub');

        CREATE POLICY "Users can insert own weight logs" ON public.weight_logs
            FOR INSERT TO authenticated
            WITH CHECK (user_id = auth.jwt()->>'sub');

        CREATE POLICY "Users can update own weight logs" ON public.weight_logs
            FOR UPDATE TO authenticated
            USING (user_id = auth.jwt()->>'sub')
            WITH CHECK (user_id = auth.jwt()->>'sub');

        CREATE POLICY "Users can delete own weight logs" ON public.weight_logs
            FOR DELETE TO authenticated
            USING (user_id = auth.jwt()->>'sub');
    END IF;
END
$$;

-- Backup tables created by the Clerk-safe table switch may retain policies from
-- the old UUID tables. They are not runtime surfaces, so leave them private.
DO $$
DECLARE
    table_name TEXT;
    policy_record RECORD;
BEGIN
    FOREACH table_name IN ARRAY ARRAY[
        'profiles_old',
        'body_metrics_old',
        'daily_metrics_old',
        'progress_photos_old',
        'weight_logs_old',
        'email_subscriptions_old'
    ]
    LOOP
        IF EXISTS (
            SELECT 1
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public'
              AND c.relname = table_name
              AND c.relkind IN ('r', 'p')
        ) THEN
            EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', table_name);
            EXECUTE format('REVOKE ALL ON TABLE public.%I FROM anon, authenticated', table_name);

            FOR policy_record IN
                SELECT policyname
                FROM pg_policies
                WHERE schemaname = 'public'
                  AND tablename = table_name
            LOOP
                EXECUTE format(
                    'DROP POLICY IF EXISTS %I ON public.%I',
                    policy_record.policyname,
                    table_name
                );
            END LOOP;
        END IF;
    END LOOP;
END
$$;

-- Remove permissive storage policies and reassert per-user photo storage access.
DROP POLICY IF EXISTS "Authenticated users can manage photos" ON storage.objects;
DROP POLICY IF EXISTS "Public photo access" ON storage.objects;
DROP POLICY IF EXISTS "Anyone can view photos" ON storage.objects;
DROP POLICY IF EXISTS "Users can upload own photos" ON storage.objects;
DROP POLICY IF EXISTS "Users can view own photos" ON storage.objects;
DROP POLICY IF EXISTS "Users can update own photos" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete own photos" ON storage.objects;

CREATE POLICY "Users can upload own photos" ON storage.objects
    FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'photos' AND
        (storage.foldername(name))[1] = auth.jwt()->>'sub'
    );

CREATE POLICY "Users can view own photos" ON storage.objects
    FOR SELECT TO authenticated
    USING (
        bucket_id = 'photos' AND
        (storage.foldername(name))[1] = auth.jwt()->>'sub'
    );

CREATE POLICY "Users can update own photos" ON storage.objects
    FOR UPDATE TO authenticated
    USING (
        bucket_id = 'photos' AND
        (storage.foldername(name))[1] = auth.jwt()->>'sub'
    )
    WITH CHECK (
        bucket_id = 'photos' AND
        (storage.foldername(name))[1] = auth.jwt()->>'sub'
    );

CREATE POLICY "Users can delete own photos" ON storage.objects
    FOR DELETE TO authenticated
    USING (
        bucket_id = 'photos' AND
        (storage.foldername(name))[1] = auth.jwt()->>'sub'
    );

-- Fail the migration if any authenticated or public policy still grants blanket
-- access to user-owned health or photo data.
DO $$
DECLARE
    insecure_policy RECORD;
BEGIN
    SELECT schemaname, tablename, policyname, qual, with_check
    INTO insecure_policy
    FROM pg_policies
    WHERE (
        schemaname = 'public'
        AND tablename = ANY(ARRAY[
            'profiles',
            'body_metrics',
            'daily_metrics',
            'progress_photos',
            'email_subscriptions',
            'profiles_old',
            'body_metrics_old',
            'daily_metrics_old',
            'progress_photos_old',
            'weight_logs_old',
            'email_subscriptions_old'
        ])
        OR (schemaname = 'storage' AND tablename = 'objects')
    )
      AND ('authenticated' = ANY(roles) OR 'public' = ANY(roles))
      AND (
        COALESCE(qual, '') IN ('true', '(true)')
        OR COALESCE(with_check, '') IN ('true', '(true)')
      )
    LIMIT 1;

    IF FOUND THEN
        RAISE EXCEPTION
            'Permissive RLS policy remains on %.%: %',
            insecure_policy.schemaname,
            insecure_policy.tablename,
            insecure_policy.policyname;
    END IF;
END
$$;
