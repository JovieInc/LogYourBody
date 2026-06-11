# Supabase Edge Functions

## Setup

1. Install Supabase CLI if not already installed:

```bash
brew install supabase/tap/supabase
```

2. Link your project:

```bash
supabase link --project-ref your-project-ref
```

3. Set up environment variables:

```bash
# Copy the example env file
cp .env.example .env

# Edit .env with your Cloudinary credentials
# Get these from https://cloudinary.com/console

# Set the secrets in Supabase
supabase secrets set CLOUDINARY_CLOUD_NAME=your_cloud_name
supabase secrets set CLOUDINARY_API_KEY=your_api_key
supabase secrets set CLOUDINARY_API_SECRET=your_api_secret
```

## Deploy Functions

Deploy the process-progress-photo function:

```bash
supabase functions deploy process-progress-photo
```

## Storage Setup

Make sure you have a storage bucket named `photos`:

```sql
-- Run this in Supabase SQL Editor
INSERT INTO storage.buckets (id, name, public)
VALUES ('photos', 'photos', false)
ON CONFLICT (id) DO NOTHING;

-- Set up RLS policies
CREATE POLICY "Users can upload their own photos" ON storage.objects
FOR INSERT WITH CHECK (
  bucket_id = 'photos' AND
  auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "Users can view their own photos" ON storage.objects
FOR SELECT USING (
  bucket_id = 'photos' AND
  auth.uid()::text = (storage.foldername(name))[1]
);

-- Processed photos are served from Cloudinary after the function verifies ownership.
-- Keep original uploads private in Supabase Storage.
```

## Database Schema Update

Add the photo-related columns to body_metrics table:

```sql
-- Add photo URL columns if they don't exist
ALTER TABLE body_metrics
ADD COLUMN IF NOT EXISTS photo_url TEXT,
ADD COLUMN IF NOT EXISTS original_photo_url TEXT,
ADD COLUMN IF NOT EXISTS photo_processed_at TIMESTAMP WITH TIME ZONE;

-- Add index for faster queries
CREATE INDEX IF NOT EXISTS idx_body_metrics_photo_url ON body_metrics(photo_url) WHERE photo_url IS NOT NULL;
```

## Testing

Test the function locally:

```bash
supabase functions serve process-progress-photo
```

Call the function:

```bash
curl -i --location --request POST 'http://localhost:54321/functions/v1/process-progress-photo' \
  --header 'apikey: YOUR_SUPABASE_ANON_KEY' \
  --header 'Authorization: Bearer YOUR_USER_JWT' \
  --header 'Content-Type: application/json' \
  --data '{"storagePath":"user_123/test-123-progress.jpg","metricsId":"test-123"}'
```

## Monitoring

View function logs:

```bash
supabase functions logs process-progress-photo
```
