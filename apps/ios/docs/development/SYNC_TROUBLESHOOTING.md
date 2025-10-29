# iOS App Sync Troubleshooting Guide

## Overview
The iOS app uses Clerk for authentication and syncs data to Supabase. For sync to work properly, several components need to be configured correctly.

## Prerequisites

### 1. Supabase JWT Configuration
Supabase needs to be configured to accept Clerk's JWT tokens. This is done in the Supabase dashboard:

1. Go to your Supabase project dashboard
2. Navigate to Settings → Authentication
3. Under "JWT Settings", configure:
   - **JWT Secret**: Get this from Clerk dashboard → JWT Templates → Default (or create a "supabase" template)
   - **JWT Algorithm**: Should match Clerk's (typically RS256)
   - **JWT Issuer**: Your Clerk instance URL (e.g., `https://your-app.clerk.accounts.dev`)

### 2. Clerk JWT Template (Optional)
If using a custom JWT template named "supabase":

1. Go to Clerk dashboard → JWT Templates
2. Create new template named "supabase"
3. Add claims:
   ```json
   {
     "sub": "{{user.id}}",
     "email": "{{user.primary_email_address}}",
     "role": "authenticated"
   }
   ```

### 3. Database Tables
Ensure the following tables exist (without `_new` suffix after migration 20250704000004):
- `profiles`
- `body_metrics`
- `daily_metrics`
- `progress_photos`
- `weight_logs`
- `email_subscriptions`

## Debugging Sync Issues

### 1. Check Console Logs
The app now includes detailed logging for sync operations:

```
🔧 Initializing Clerk SDK
✅ Clerk SDK loaded successfully
🔐 Got JWT token from Clerk
🔑 Token preview: eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
📤 Syncing 1 body metrics...
🚀 Sending body metrics to Supabase: <metric-id>
✅ Successfully saved body metrics to Supabase
```

### 2. Common Error Messages

#### "Unauthorized - JWT token may be invalid"
- Supabase is rejecting the JWT token
- Check Supabase JWT configuration matches Clerk's settings
- Verify the JWT secret is correct

#### "No 'supabase' JWT template found, using default token"
- This is a warning, not an error
- The app will try to use Clerk's default JWT token
- If sync fails, you may need to create a "supabase" JWT template in Clerk

#### HTTP Error 400/404
- Check that the table names are correct (should NOT have `_new` suffix after migration)
- Verify the RLS policies are properly configured
- Ensure all migrations have been applied, especially 20250704000004_switch_to_new_tables.sql

### 3. Verify RLS Policies
Run this SQL in Supabase SQL editor to check policies:

```sql
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual 
FROM pg_policies 
WHERE schemaname = 'public' 
AND tablename IN ('profiles', 'body_metrics', 'daily_metrics', 'progress_photos', 'weight_logs', 'email_subscriptions');
```

### 4. Test JWT Token
To verify the JWT token is valid:

1. Copy the token preview from console logs
2. Go to jwt.io and paste the full token
3. Verify:
   - `sub` claim contains the Clerk user ID
   - `iss` claim matches your Clerk instance
   - Token is not expired

### 5. Manual Sync Test
Force a sync from the app:
1. Open the Dashboard
2. Look for "X items pending sync" message
3. Tap "Sync Now" button
4. Check console logs for results

## Database Migrations

If tables are missing, run the migration:

```bash
cd /Users/timwhite/Documents/GitHub/TBF/LogYourBody
npx supabase db push --password <your-password>
```

## Additional Notes

- Sync runs automatically every 5 minutes when the app is active
- Sync also runs when network becomes available
- Data is stored locally in Core Data until successfully synced
- The sync status icon shows:
  - 🔄 (rotating arrows) = Currently syncing
  - ⚠️ (exclamation cloud) = Items pending sync