# Vercel Environment Variables Checklist

## 📋 Instructions
1. Go to your Vercel project dashboard
2. Navigate to: **Settings** → **Environment Variables**
3. Add each variable below
4. For each variable, select: **Production**, **Preview**, and **Development** (unless noted otherwise)

## ✅ Required Variables

### Supabase (Database & Storage)
```
NEXT_PUBLIC_SUPABASE_URL
NEXT_PUBLIC_SUPABASE_ANON_KEY
SUPABASE_SERVICE_ROLE_KEY
SUPABASE_JWT_SECRET
POSTGRES_DATABASE
```

**Where to find these**:
- Supabase Dashboard → Project Settings → API
- Or copy from your local `.env.local` file

### Clerk (Authentication)
```
NEXT_PUBLIC_CLERK_PUBLISHABLE_KEY
CLERK_SECRET_KEY
CLERK_WEBHOOK_SECRET
```

**Where to find these**:
- Clerk Dashboard → API Keys
- Webhook secret: Clerk Dashboard → Webhooks → Endpoint Settings

### RevenueCat (Subscriptions)
```
NEXT_PUBLIC_REVENUECAT_PUBLIC_KEY
REVENUECAT_PUBLIC_KEY
```

**Where to find these**:
- RevenueCat Dashboard → Project Settings → API Keys

## 🔍 Optional but Recommended Variables

### OpenAI (Avatar Generation)
```
OPENAI_API_KEY
```

**Where to find this**:
- OpenAI Dashboard → API Keys
- Only needed if using AI avatar generation features

### Stripe (Direct Payments - if used)
```
STRIPE_ANNUAL_PRICE_ID
STRIPE_ANNUAL_PRODUCT_ID
STRIPE_MONTHLY_PRICE_ID
STRIPE_MONTHLY_PRODUCT_ID
```

**Where to find these**:
- Stripe Dashboard → Products
- Only needed if using Stripe directly (not through RevenueCat)

### Twilio (SMS Authentication)
```
TWILIO_ACCOUNT_SID
TWILIO_AUTH_TOKEN
TWILIO_PHONE_NUMBER
```

**Where to find these**:
- Twilio Console → Account Info
- Only needed if using SMS-based authentication

## ⚙️ Auto-Generated Variables

These are automatically set by Vercel - **DO NOT** add manually:
```
VERCEL_URL
VERCEL_ENV
VERCEL_GIT_COMMIT_SHA
VERCEL_GIT_COMMIT_REF
```

## 🔒 Security Notes

1. **Never** commit actual secrets to git
2. Use different keys for Production vs Development when possible
3. Rotate secrets regularly (every 90 days recommended)
4. Review access logs in your service dashboards periodically

## ✅ Verification

After adding all variables:

1. Trigger a new deployment:
   ```bash
   git commit --allow-empty -m "Test Vercel env vars"
   git push
   ```

2. Check deployment logs for:
   - No "Missing environment variable" errors
   - Successful build completion
   - Successful deployment

3. Test the deployed app:
   - Visit your Vercel URL
   - Try to sign in (Clerk should work)
   - Check that data loads (Supabase should work)
   - Verify subscriptions (RevenueCat should work)

## 🚨 Troubleshooting

### Error: "Missing environment variable"
- Double-check variable name spelling (exact match required)
- Ensure variable is set for the correct environment (Production/Preview/Development)
- Redeploy after adding variables

### Error: "Invalid API key"
- Verify you copied the entire key (no spaces/newlines)
- Check you're using the correct key for the environment (live vs test)
- Regenerate the key if needed

### Error: "Unauthorized" or "403 Forbidden"
- Check that service role keys (Supabase, Clerk) are correct
- Verify JWT secrets match between services
- Check Clerk webhook secret matches your webhook endpoint

## 📚 References

- [Vercel Environment Variables Docs](https://vercel.com/docs/projects/environment-variables)
- [Clerk Environment Variables](https://clerk.com/docs/deployments/set-up-production-instance)
- [Supabase Environment Variables](https://supabase.com/docs/guides/getting-started/quickstarts/nextjs)
- [RevenueCat API Keys](https://www.revenuecat.com/docs/authentication)

---

**Last Updated**: 2025-11-11
