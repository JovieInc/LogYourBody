# Vercel Deployment Configuration for LogYourBody Monorepo

## ⚠️ Problem
The Next.js app builds successfully locally but fails on Vercel because Vercel needs special configuration for monorepo projects.

## ✅ Local Build Status
```bash
✓ Compiled successfully in 4.0s
✓ Generating static pages (76/76)
BUILD SUCCEEDED
```

## 🔧 Required Vercel Configuration

### 1. Project Settings (Vercel Dashboard)

Navigate to your project settings in Vercel Dashboard → Settings → General

#### Root Directory
- **Set to**: `apps/web`
- **Why**: Tells Vercel where the Next.js app is located in the monorepo

#### Build & Development Settings

**Framework Preset**: Next.js

**Build Command**:
```bash
npm run build
```
OR if that doesn't work:
```bash
cd ../.. && npm run build --workspace=apps/web
```

**Output Directory**: `.next` (default, leave as-is)

**Install Command**:
```bash
npm install
```
OR if dependencies fail:
```bash
cd ../.. && npm install
```

#### Node.js Version
- **Set to**: `20.x` or higher
- **Why**: package.json requires `node >= 20.0.0`
- **Location**: Settings → General → Node.js Version

### 2. Environment Variables (CRITICAL)

Navigate to: Settings → Environment Variables

Add these variables (get values from your `.env.local`):

#### Required Variables:
```
NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY=pk_live_...
CLERK_SECRET_KEY=sk_live_...
CLERK_WEBHOOK_SECRET=whsec_...
NEXT_PUBLIC_SUPABASE_URL=https://ihivupqpctpkrgqgxfjf.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGc...
SUPABASE_SERVICE_ROLE_KEY=eyJhbGc...
SUPABASE_JWT_SECRET=your-jwt-secret
POSTGRES_DATABASE=postgres
```

#### Optional but Recommended:
```
NEXT_PUBLIC_REVENUECAT_PUBLIC_KEY=your-key
OPENAI_API_KEY=sk-...
TWILIO_ACCOUNT_SID=AC...
TWILIO_AUTH_TOKEN=...
TWILIO_PHONE_NUMBER=+1...
```

**Important**: Set all variables for "Production", "Preview", and "Development" environments unless you have environment-specific values.

### 3. Deployment Configuration

The project has two deployment configuration options:

#### Option A: Root-level vercel.json (Recommended)
A `vercel.json` file has been created at the repository root that tells Vercel how to build the monorepo:

```json
{
  "buildCommand": "npm run build --workspace=apps/web",
  "outputDirectory": "apps/web/.next",
  "installCommand": "npm install",
  "framework": "nextjs"
}
```

With this file, Vercel will automatically:
- Install dependencies from the root
- Build the web app using the workspace command
- Deploy from the correct output directory

#### Option B: Manual Vercel Dashboard Configuration
If Option A doesn't work, configure manually in Vercel Dashboard (see Section 1 above).

#### Existing Configuration Files:
- ✅ `vercel.json` (root) - Monorepo build configuration
- ✅ `apps/web/vercel.json` - Headers and framework config
- ✅ `apps/web/.vercelignore` - Excludes unnecessary files
- ✅ `turbo.json` - Build pipeline configuration
- ✅ `apps/web/next.config.ts` - Next.js configuration

### 4. Common Monorepo Issues & Solutions

#### Issue: "Could not find package.json"
**Solution**: Set Root Directory to `apps/web`

#### Issue: "Module not found" errors during build
**Solution**: Ensure Install Command is `npm install` (not `npm ci`)

#### Issue: "Node version too old"
**Solution**: Set Node.js version to 20.x in project settings

#### Issue: TypeScript errors during build
**Solution**: Check that all required environment variables are set in Vercel
- Missing env vars can cause TypeScript to fail type-checking

#### Issue: Build succeeds but runtime errors
**Solution**:
1. Check browser console for missing environment variables
2. Ensure all `NEXT_PUBLIC_*` variables are set in Vercel
3. Check that Clerk and Supabase URLs are correct

### 5. Verification Steps

After configuring Vercel:

1. **Trigger a new deployment**:
   ```bash
   git commit --allow-empty -m "Trigger Vercel deployment"
   git push
   ```

2. **Check build logs** in Vercel dashboard for:
   - ✓ Correct Node version (should show v20.x)
   - ✓ Dependencies installed from root
   - ✓ Build running from apps/web
   - ✓ No TypeScript errors
   - ✓ Successful deployment

3. **Test the deployed site**:
   - Visit your Vercel URL
   - Check that authentication works (Clerk)
   - Verify database connections (Supabase)
   - Test creating an entry

### 6. Debug Failed Builds

If build still fails, check these in order:

1. **View full build logs** in Vercel dashboard
2. **Look for**:
   - Missing environment variables
   - TypeScript compilation errors
   - Module resolution issues
   - Memory/timeout issues

3. **Common error patterns**:

   **"Cannot find module '@/...'"**
   - Check that `tsconfig.json` paths are correct
   - Verify Root Directory is set to `apps/web`

   **"Environment variable not found"**
   - Add missing variables in Vercel settings
   - Ensure they're set for the correct environment (Production/Preview)

   **"Out of memory"**
   - Contact Vercel support to increase memory limit
   - Or optimize build by reducing bundle size

## 📋 Quick Setup Checklist

- [ ] Set Root Directory to `apps/web`
- [ ] Set Node.js version to `20.x`
- [ ] Configure Build Command: `npm run build`
- [ ] Configure Install Command: `npm install`
- [ ] Add all required environment variables
- [ ] Add all `NEXT_PUBLIC_*` variables (frontend needs these!)
- [ ] Deploy and check build logs
- [ ] Test deployed site thoroughly

## 🔗 Helpful Links

- [Vercel Monorepo Documentation](https://vercel.com/docs/monorepos)
- [Next.js on Vercel](https://vercel.com/docs/frameworks/nextjs)
- [Environment Variables](https://vercel.com/docs/projects/environment-variables)

## 💡 Tips

- Use Vercel's deployment logs to debug issues
- Test environment variables locally first with `.env.local`
- Keep `.env.example` up to date for team members
- Never commit actual secrets to git
- Use Vercel's Preview Deployments to test changes before production

## 🎯 Expected Result

After proper configuration, you should see:
```
✓ Creating an optimized production build
✓ Compiled successfully
✓ Generating static pages (76/76)
✓ Finalizing page optimization
✓ Deployment complete
```

---

**Last Updated**: 2025-11-11
**Status**: ✅ Local builds working, Vercel configuration needed
