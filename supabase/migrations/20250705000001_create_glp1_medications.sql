-- Create table for GLP-1 medications and link dose logs to medications
CREATE TABLE IF NOT EXISTS public.glp1_medications (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL,
    generic_name TEXT,
    drug_class TEXT,
    brand TEXT,
    route TEXT,
    frequency TEXT,
    dose_unit TEXT,
    is_compounded BOOLEAN DEFAULT FALSE,
    hk_identifier TEXT,
    started_at TIMESTAMP WITH TIME ZONE NOT NULL,
    ended_at TIMESTAMP WITH TIME ZONE,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_glp1_medications_user_id ON public.glp1_medications(user_id);
CREATE INDEX IF NOT EXISTS idx_glp1_medications_started_at ON public.glp1_medications(started_at DESC);

ALTER TABLE public.glp1_medications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own glp1 medications" ON public.glp1_medications
    FOR SELECT TO authenticated
    USING (user_id = auth.jwt()->>'sub');

CREATE POLICY "Users can insert own glp1 medications" ON public.glp1_medications
    FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.jwt()->>'sub');

CREATE POLICY "Users can update own glp1 medications" ON public.glp1_medications
    FOR UPDATE TO authenticated
    USING (user_id = auth.jwt()->>'sub')
    WITH CHECK (user_id = auth.jwt()->>'sub');

CREATE POLICY "Users can delete own glp1 medications" ON public.glp1_medications
    FOR DELETE TO authenticated
    USING (user_id = auth.jwt()->>'sub');

CREATE TRIGGER update_glp1_medications_updated_at
    BEFORE UPDATE ON public.glp1_medications
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();

-- Link GLP-1 dose logs to medications
ALTER TABLE public.glp1_dose_logs
    ADD COLUMN IF NOT EXISTS medication_id UUID REFERENCES public.glp1_medications(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_glp1_dose_logs_medication_id ON public.glp1_dose_logs(medication_id);
