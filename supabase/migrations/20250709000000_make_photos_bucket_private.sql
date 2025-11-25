-- Make photos storage bucket private and remove public read access

-- Set the photos bucket to private
UPDATE storage.buckets
SET public = false
WHERE id = 'photos';

-- Remove public read access policy, if it exists
DROP POLICY IF EXISTS "Anyone can view photos" ON storage.objects;

-- Per-user Clerk-based RLS policies created in earlier migrations remain in place
-- and continue to control access to objects in the photos bucket.
