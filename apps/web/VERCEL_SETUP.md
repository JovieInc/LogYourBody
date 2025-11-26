# Vercel Setup Guide

## Current Issue

The Vercel deployments are failing because:
1. Environment variables are not configured in Vercel
2. The Vercel GitHub integration may not be properly set up

## Steps to Fix

### 1. Configure Vercel Environment Variables

1. Go to [Vercel Dashboard](https://vercel.com/dashboard)
2. Select your `LogYourBody` project
3. Go to **Settings** → **Environment Variables**
4. Add the following variables for ALL environments (Production, Preview, Development):

```bash
NEXT_PUBLIC_SUPABASE_URL=https://przjeunffnkjzxpykvjn.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InByempldW5mZm5ranp4cHlrdmpuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NDk0MTI1NDYsImV4cCI6MjA2NDk4ODU0Nn0.jZyohfzoydZKaSH_q0Tu4VqEbyFDdf-8i0kSm-YzB8w
```

### 2. Verify Vercel GitHub Integration

1. Go to **Settings** → **Git** in your Vercel project
2. Ensure the repository `JovieInc/LogYourBody` is connected
3. Make sure **"Create deployments for every push"** is enabled
4. Verify that the Vercel bot has access to create deployments and comments

### 3. Enable Vercel Bot Comments

1. In Vercel project settings, go to **Git** → **Comments**
2. Enable **"Comment on Pull Requests"**
3. This allows the CI workflow to detect Vercel deployments

### 4. Alternative: Remove Vercel Check from CI

If Vercel integration cannot be fixed, you can temporarily disable the Vercel check:

1. Edit `.github/workflows/ci.yml`
2. Remove `wait-for-vercel` from the `needs` array in `create-pr-to-preview`
3. This will allow auto-merge without waiting for Vercel

## Build Configuration

The app is now configured to build successfully even without Supabase environment variables:
- Missing credentials will show a warning banner
- Authentication features will be disabled
- The app will run in "demo mode"

## Testing

After adding environment variables to Vercel:
1. Push a commit to trigger a new deployment
2. Check the deployment logs in Vercel dashboard
3. Verify the deployment succeeds
4. The CI workflow should then pass the Vercel check