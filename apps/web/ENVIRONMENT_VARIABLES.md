# Environment Variables Configuration

This document describes the environment variables required for LogYourBody.

## Required Environment Variables

### Waitlist storage

```bash
# Server-only pooled Neon connection for pre-launch email capture.
# Never expose this through a NEXT_PUBLIC_ variable.
WAITLIST_DATABASE_URL=postgresql://...
```

The waitlist database is isolated from Jovie's application database and from
LogYourBody's future authenticated product data. Its schema lives in
`apps/web/db/migrations` and is accessed only through the internal waitlist
storage port.

### Supabase Configuration

These variables are required for authentication and database functionality:

```bash
# Supabase API URL
NEXT_PUBLIC_SUPABASE_URL=https://your-project.supabase.co

# Supabase Anonymous Key (safe for client-side)
NEXT_PUBLIC_SUPABASE_ANON_KEY=your-anon-key

# Supabase Service Role Key (server-side only, DO NOT expose to client)
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key

# Supabase JWT Secret (for webhook validation)
SUPABASE_JWT_SECRET=your-jwt-secret
```

### Database Configuration

```bash
# PostgreSQL Database URL
POSTGRES_DATABASE=postgres
```

### AI Integration (Optional)

```bash
# OpenAI API Key (for PDF parsing of body composition reports)
OPENAI_API_KEY=your-openai-api-key
```

## Deployment Platforms

### Vercel

1. Go to your project settings on Vercel
2. Navigate to "Environment Variables"
3. Add each variable listed above
4. Make sure to set them for all environments (Production, Preview, Development)

### Local Development

1. Copy `.env.example` to `.env.local`
2. Fill in your Supabase project details
3. Never commit `.env.local` to version control

## Getting Supabase Credentials

1. Create a project at [supabase.com](https://supabase.com)
2. Go to Project Settings > API
3. Copy the Project URL and anon key
4. The service role key is found in the same section (keep this secret!)

## Build-Time Behavior

The application is configured to build successfully even without Supabase credentials:

- Missing credentials will show a warning banner
- Authentication features will be disabled
- The app will run in "demo mode"

This allows for deployment previews and development without requiring database access.
