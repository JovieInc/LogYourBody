-- Add separate first and last name columns to profile tables

-- Primary profiles table used by current clients
ALTER TABLE IF EXISTS public.profiles
    ADD COLUMN IF NOT EXISTS first_name text,
    ADD COLUMN IF NOT EXISTS last_name text;

-- Clerk-safe profiles table used by the new TEXT-id migration path
ALTER TABLE IF EXISTS public.profiles_new
    ADD COLUMN IF NOT EXISTS first_name text,
    ADD COLUMN IF NOT EXISTS last_name text;
