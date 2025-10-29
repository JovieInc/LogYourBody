# Step-by-Step Guide to Set Up RLS Policies in Supabase

## Prerequisites
1. Access to your Supabase project dashboard
2. Clerk configured as an auth provider in Supabase
3. Tables created (body_metrics, daily_metrics, user_profiles/profiles)

## Step 1: Configure Clerk in Supabase

1. Go to your Supabase Dashboard
2. Navigate to **Authentication** → **Providers**
3. Find and enable **Custom** provider (this is where Clerk will be configured)
4. Configure with these settings:
   - **Client ID**: Your Clerk Frontend API (found in Clerk Dashboard)
   - **Secret**: Not needed for JWT validation
   - **Authorize URL**: `https://YOUR-CLERK-DOMAIN.clerk.accounts.dev/oauth/authorize`
   - **Token URL**: `https://YOUR-CLERK-DOMAIN.clerk.accounts.dev/oauth/token`
   - **User URL**: `https://YOUR-CLERK-DOMAIN.clerk.accounts.dev/oauth/userinfo`

## Step 2: Set Up RLS Policies

1. Go to **SQL Editor** in your Supabase dashboard
2. Copy the contents of `supabase_rls_setup.sql` 
3. Run the script section by section:

### Option A: Run All at Once
- Paste the entire SQL script and click "Run"

### Option B: Run Section by Section (Recommended for debugging)

#### First, test the JWT:
```sql
-- This shows what Clerk is sending
SELECT auth.jwt() as current_jwt;
```

#### Then enable RLS for each table:
```sql
-- For body_metrics
ALTER TABLE body_metrics ENABLE ROW LEVEL SECURITY;

-- For daily_metrics  
ALTER TABLE daily_metrics ENABLE ROW LEVEL SECURITY;
```

#### Create policies for each table (run each policy separately to catch any errors):
```sql
-- Example for body_metrics read policy
CREATE POLICY "Users can read own body metrics" ON body_metrics
    FOR SELECT
    USING (auth.jwt() ->> 'sub' = user_id);
```

## Step 3: Verify the Setup

Run these verification queries:

```sql
-- Check RLS is enabled
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public' 
  AND tablename IN ('body_metrics', 'daily_metrics', 'user_profiles');

-- Check policies exist
SELECT tablename, policyname, cmd 
FROM pg_policies 
WHERE schemaname = 'public'
ORDER BY tablename;
```

## Step 4: Test with Your App

1. Open Xcode and run the LogYourBody app
2. Sign in with a Clerk account
3. Check the console logs for sync messages
4. Try to sync some data
5. Check Supabase logs for any errors

## Troubleshooting

### Issue: "column auth.jwt does not exist"
**Solution**: Make sure Clerk is properly configured as an auth provider in Supabase

### Issue: "permission denied for table"
**Solution**: 
1. Check that RLS is enabled on the table
2. Verify the JWT contains the expected user ID
3. Run this debug query:
```sql
SELECT 
    auth.jwt() ->> 'sub' as clerk_user_id,
    auth.jwt() -> 'email' as user_email;
```

### Issue: Data syncs but can't be read back
**Solution**: The user_id in your table might not match the Clerk user ID. Check with:
```sql
-- See what user_ids are in your table
SELECT DISTINCT user_id FROM body_metrics LIMIT 10;

-- Compare with Clerk JWT
SELECT auth.jwt() ->> 'sub' as clerk_user_id;
```

### Issue: "JWT expired" or "JWT invalid"
**Solution**: 
1. Make sure you're using the latest Clerk-Supabase integration
2. The app should be getting fresh tokens with: `session.getToken()`
3. Check that your Supabase project's JWT secret matches Clerk's signing key

## Alternative: Disable RLS for Testing

If you want to test without RLS first:
```sql
-- Disable RLS temporarily
ALTER TABLE body_metrics DISABLE ROW LEVEL SECURITY;
ALTER TABLE daily_metrics DISABLE ROW LEVEL SECURITY;
```

**⚠️ WARNING**: Only do this for testing! Re-enable RLS before going to production.

## Next Steps

Once RLS is working:
1. Test creating data from the app
2. Verify data appears in Supabase with correct user_id
3. Test reading data back
4. Monitor Supabase logs for any policy violations