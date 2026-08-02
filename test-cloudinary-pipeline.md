# Testing Cloudinary Pipeline

## 1. Check Edge Function Deployment

First, verify the edge function is deployed:

```bash
# Check if edge function is deployed
supabase functions list

# Deploy if needed
supabase functions deploy process-progress-photo
```

## 2. Check Environment Variables

Ensure these are set in Supabase dashboard:

- CLOUDINARY_CLOUD_NAME
- CLOUDINARY_API_KEY
- CLOUDINARY_API_SECRET

## 3. Test Upload Flow

1. Take or select a photo in the iOS app
2. Check Xcode console for logs:
   - "📸 PhotoUploadManager: Starting upload..."
   - "📸 PhotoUploadManager: Uploading to Supabase Storage..."
   - "📸 PhotoUploadManager: Calling edge function..."
   - "✅ PhotoUploadManager: Processing complete..."

## 4. Verify Results

1. Check Supabase Storage:
   - Go to Storage > photos bucket
   - Look for user_id/metrics_id_timestamp.jpg

2. Check Cloudinary Dashboard:
   - Look for processed images under `progress-photos/<user_id>/<metric_id>_<timestamp>`

3. Check Database:
   - body_metrics table should have:
     - photo_url (Cloudinary processed URL)
     - original_photo_url (Supabase storage URL)
     - photo_processed_at timestamp

## 5. Common Issues

### Storage Upload Fails

- Check authentication token is valid
- Verify bucket policies allow upload
- Check file size is under 10MB

### Edge Function Fails

- Check Cloudinary credentials are set
- Verify edge function is deployed
- Check edge function logs: `supabase functions logs process-progress-photo`

### No Background Removal

- Verify Cloudinary plan includes AI background removal
- Check transformation string in edge function

## 6. Debug Commands

```bash
# View edge function logs
supabase functions logs process-progress-photo --tail

# Test edge function locally
supabase functions serve process-progress-photo

# Check storage bucket
supabase storage ls photos
```
