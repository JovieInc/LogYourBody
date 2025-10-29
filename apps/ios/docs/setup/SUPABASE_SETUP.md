# Supabase Setup for Clerk Integration

This document outlines the required Supabase configuration for the LogYourBody iOS app using the new Clerk-Supabase native integration pattern.

## Prerequisites

1. Clerk application configured and running
2. Supabase project created
3. Both services properly configured in the iOS app

## Supabase Configuration

### 1. Configure Clerk as Auth Provider

In your Supabase dashboard:
1. Go to Authentication → Providers
2. Add Clerk as a third-party provider
3. Configure with your Clerk domain (found in Clerk dashboard)

### 2. Row Level Security (RLS) Policies

The app uses Clerk JWTs directly, so RLS policies must be configured to extract the user ID from the Clerk JWT.

#### Body Metrics Table
```sql
-- Enable RLS
ALTER TABLE body_metrics ENABLE ROW LEVEL SECURITY;

-- Policy for users to read their own data
CREATE POLICY "Users can read own body metrics" ON body_metrics
    FOR SELECT
    USING (auth.jwt() ->> 'sub' = user_id);

-- Policy for users to insert their own data
CREATE POLICY "Users can insert own body metrics" ON body_metrics
    FOR INSERT
    WITH CHECK (auth.jwt() ->> 'sub' = user_id);

-- Policy for users to update their own data
CREATE POLICY "Users can update own body metrics" ON body_metrics
    FOR UPDATE
    USING (auth.jwt() ->> 'sub' = user_id)
    WITH CHECK (auth.jwt() ->> 'sub' = user_id);

-- Policy for users to delete their own data
CREATE POLICY "Users can delete own body metrics" ON body_metrics
    FOR DELETE
    USING (auth.jwt() ->> 'sub' = user_id);
```

#### Daily Metrics Table
```sql
-- Enable RLS
ALTER TABLE daily_metrics ENABLE ROW LEVEL SECURITY;

-- Policy for users to read their own data
CREATE POLICY "Users can read own daily metrics" ON daily_metrics
    FOR SELECT
    USING (auth.jwt() ->> 'sub' = user_id);

-- Policy for users to insert their own data
CREATE POLICY "Users can insert own daily metrics" ON daily_metrics
    FOR INSERT
    WITH CHECK (auth.jwt() ->> 'sub' = user_id);

-- Policy for users to update their own data
CREATE POLICY "Users can update own daily metrics" ON daily_metrics
    FOR UPDATE
    USING (auth.jwt() ->> 'sub' = user_id)
    WITH CHECK (auth.jwt() ->> 'sub' = user_id);

-- Policy for users to delete their own data
CREATE POLICY "Users can delete own daily metrics" ON daily_metrics
    FOR DELETE
    USING (auth.jwt() ->> 'sub' = user_id);
```

#### User Profiles Table
```sql
-- Enable RLS
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;

-- Policy for users to read their own profile
CREATE POLICY "Users can read own profile" ON user_profiles
    FOR SELECT
    USING (auth.jwt() ->> 'sub' = id);

-- Policy for users to insert their own profile
CREATE POLICY "Users can insert own profile" ON user_profiles
    FOR INSERT
    WITH CHECK (auth.jwt() ->> 'sub' = id);

-- Policy for users to update their own profile
CREATE POLICY "Users can update own profile" ON user_profiles
    FOR UPDATE
    USING (auth.jwt() ->> 'sub' = id)
    WITH CHECK (auth.jwt() ->> 'sub' = id);
```

## Important Notes

1. **User ID Mapping**: The `auth.jwt() ->> 'sub'` extracts the Clerk user ID from the JWT. This must match the `user_id` field in your tables.

2. **No JWT Templates**: As of April 2025, Clerk JWT templates are deprecated. The app now uses standard Clerk session tokens directly.

3. **Token Usage**: The iOS app gets tokens using:
   ```swift
   let tokenResource = try await session.getToken()
   let token = tokenResource?.jwt
   ```

4. **Testing**: After setting up RLS policies, test by:
   - Creating a test user in Clerk
   - Logging in with the iOS app
   - Attempting to sync data
   - Verifying data appears in Supabase with correct user_id

## Troubleshooting

If sync is not working:

1. **Check Supabase Logs**: Go to Database → Logs in Supabase dashboard
2. **Verify JWT**: Use jwt.io to decode the Clerk JWT and ensure the 'sub' claim contains the user ID
3. **Test RLS Policies**: Use Supabase SQL editor to test policies:
   ```sql
   -- Test what the JWT contains
   SELECT auth.jwt();
   
   -- Test if user can see their data
   SELECT * FROM body_metrics WHERE auth.jwt() ->> 'sub' = user_id;
   ```

4. **Enable Detailed Logging**: The app includes extensive logging. Check Xcode console for sync-related messages.