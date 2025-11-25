-- Make photos bucket private and remove public-read policies
-- This works together with client-side use of storage paths and signed URLs.

-- Ensure the photos bucket is marked as private
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM storage.buckets WHERE id = 'photos'
  ) THEN
    UPDATE storage.buckets
    SET public = false
    WHERE id = 'photos';
  END IF;
END $$;

-- Drop legacy public-read policies if they exist
DROP POLICY IF EXISTS "Public photo access" ON storage.objects;
DROP POLICY IF EXISTS "Anyone can view photos" ON storage.objects;

-- Note: user-specific policies such as
--   "Users can upload their own photos"
--   "Users can update their own photos"
--   "Users can delete their own photos"
-- remain in place and continue to control authenticated access.
