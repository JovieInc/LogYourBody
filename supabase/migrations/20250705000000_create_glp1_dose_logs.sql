-- Create table for GLP-1 dose logs
CREATE TABLE IF NOT EXISTS public.glp1_dose_logs (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id TEXT NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    taken_at TIMESTAMP WITH TIME ZONE NOT NULL,
    dose_amount DECIMAL(10,2),
    dose_unit TEXT,
    drug_class TEXT,
    brand TEXT,
    is_compounded BOOLEAN DEFAULT FALSE,
    supplier_type TEXT,
    supplier_name TEXT,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_glp1_dose_logs_user_id ON public.glp1_dose_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_glp1_dose_logs_taken_at ON public.glp1_dose_logs(taken_at DESC);

ALTER TABLE public.glp1_dose_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own glp1 dose logs" ON public.glp1_dose_logs
    FOR SELECT TO authenticated
    USING (user_id = auth.jwt()->>'sub');

CREATE POLICY "Users can insert own glp1 dose logs" ON public.glp1_dose_logs
    FOR INSERT TO authenticated
    WITH CHECK (user_id = auth.jwt()->>'sub');

CREATE POLICY "Users can update own glp1 dose logs" ON public.glp1_dose_logs
    FOR UPDATE TO authenticated
    USING (user_id = auth.jwt()->>'sub')
    WITH CHECK (user_id = auth.jwt()->>'sub');

CREATE POLICY "Users can delete own glp1 dose logs" ON public.glp1_dose_logs
    FOR DELETE TO authenticated
    USING (user_id = auth.jwt()->>'sub');

CREATE TRIGGER update_glp1_dose_logs_updated_at
    BEFORE UPDATE ON public.glp1_dose_logs
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at_column();
