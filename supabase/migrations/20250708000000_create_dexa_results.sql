-- Create dexa_results table
CREATE TABLE IF NOT EXISTS public.dexa_results (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id TEXT NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  body_metrics_id UUID REFERENCES public.body_metrics(id) ON DELETE SET NULL,
  external_source TEXT NOT NULL DEFAULT 'bodyspec',
  external_result_id TEXT NOT NULL,
  external_update_time TIMESTAMP WITH TIME ZONE,
  scanner_model TEXT,
  location_id TEXT,
  location_name TEXT,
  acquire_time TIMESTAMP WITH TIME ZONE,
  analyze_time TIMESTAMP WITH TIME ZONE,
  vat_mass_kg NUMERIC(10,2),
  vat_volume_cm3 NUMERIC(10,2),
  result_pdf_url TEXT,
  result_pdf_name TEXT,
  composition_regions JSONB,
  bone_density_regions JSONB,
  percentiles JSONB,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW() NOT NULL
);

-- Create indexes
CREATE INDEX dexa_results_user_id_idx ON public.dexa_results(user_id);
CREATE INDEX dexa_results_body_metrics_id_idx ON public.dexa_results(body_metrics_id);
CREATE INDEX dexa_results_acquire_time_idx ON public.dexa_results(acquire_time);
CREATE UNIQUE INDEX dexa_results_external_idx
  ON public.dexa_results(user_id, external_source, external_result_id);

-- Enable RLS
ALTER TABLE public.dexa_results ENABLE ROW LEVEL SECURITY;

-- Create policies
CREATE POLICY "Users can view own DEXA results"
  ON public.dexa_results FOR SELECT TO authenticated
  USING (user_id = auth.jwt()->>'sub');

CREATE POLICY "Users can insert own DEXA results"
  ON public.dexa_results FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.jwt()->>'sub');

CREATE POLICY "Users can update own DEXA results"
  ON public.dexa_results FOR UPDATE TO authenticated
  USING (user_id = auth.jwt()->>'sub')
  WITH CHECK (user_id = auth.jwt()->>'sub');

CREATE POLICY "Users can delete own DEXA results"
  ON public.dexa_results FOR DELETE TO authenticated
  USING (user_id = auth.jwt()->>'sub');

-- Create trigger to update updated_at
CREATE TRIGGER update_dexa_results_updated_at
  BEFORE UPDATE ON public.dexa_results
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
