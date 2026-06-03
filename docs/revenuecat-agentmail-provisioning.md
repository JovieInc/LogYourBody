# RevenueCat and AgentMail Provisioning

Date: 2026-06-03

This note captures the current external setup state for the iOS paid MVP.

## Stripe Projects

- Stripe CLI is installed locally.
- Stripe Projects plugin is installed locally.
- Stripe Projects provider catalog supports AgentMail as `agentmail/api`.
- Stripe Projects provider catalog does not currently support RevenueCat.
- `stripe projects search revenuecat --json` returned `result_count: 0`.
- `stripe projects search agentmail --json` returned one available service.
- `stripe projects init` could not finish because Stripe browser auth redirected into a stuck `projects/kyc_redirect` / hCaptcha-backed flow. No local Stripe profile was created.

## AgentMail

- AgentMail CLI is installed through pnpm global tooling.
- pnpm global bin is configured in `~/.zshrc` as `PNPM_HOME=/Users/timwhite/Library/pnpm`.
- Agent inbox created: `logyourbody-codex@agentmail.to`.
- AgentMail API credentials are stored outside the repo at:
  `/Users/timwhite/.codex/secrets/logyourbody-revenuecat-agentmail.env`
- AgentMail full verification is still pending because the OTP was sent to `t@timwhite.co`, which is not the Gmail mailbox available to Codex in this session.
- The unverified AgentMail inbox can receive mail and was used to complete RevenueCat email confirmation.

## RevenueCat

- RevenueCat account email: `logyourbody-codex@agentmail.to`.
- RevenueCat email confirmation is complete.
- Project name: `LogYourBody`.
- Dashboard project id: `1f8e7a51`.
- API project id: `proj1f8e7a51`.
- Local RevenueCat credentials are stored outside the repo at:
  `/Users/timwhite/.codex/secrets/logyourbody-revenuecat-agentmail.env`
- Secret API key label: `codex-local-project-config-2026-06-03`.
- Secret API key scope: API v2, Project Configuration read/write only.
- SDK key available now: Test Store SDK key, stored in the private env file and local ignored iOS config.

## Current Offering Verification

The RevenueCat Test Store offering is configured and verified.

- Current offering: `default`.
- Entitlement display name: `Premium`.
- Monthly product:
  `com.logyourbody.app.pro.monthly.3daytrial`, duration `P1M`.
- Annual product:
  `com.logyourbody.app.pro.annual.3daytrial`, duration `P1Y`.
- Packages returned by the SDK offering endpoint:
  `$rc_monthly` and `$rc_annual`.

Verified with:

```bash
REVENUE_CAT_PUBLIC_KEY=<test-store-sdk-key> apps/ios/Scripts/verify_revenuecat_offerings.sh
```

Result:

```text
Verified RevenueCat current offering default includes $rc_annual:com.logyourbody.app.pro.annual.3daytrial, $rc_monthly:com.logyourbody.app.pro.monthly.3daytrial.
```

## Local iOS Config

The ignored local file `apps/ios/LogYourBody/Config.xcconfig` now uses the new Test Store SDK key for `REVENUE_CAT_API_KEY`, so local builds can fetch the verified offering.

## Remaining Production Blocker

This is not yet production-money-ready. RevenueCat still needs a real App Store app configuration before App Store purchases can be processed live.

RevenueCat requires an App Store Connect in-app purchase key (`SubscriptionKey_*.p8`) plus Key ID and Issuer ID for the App Store configuration. The repo references these values only through GitHub Actions secrets, which are not readable locally:

- `APP_STORE_CONNECT_API_KEY`
- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_API_KEY_ISSUER_ID`
- `APP_STORE_APP_ID`

Once that `.p8` key material is available locally or uploaded by a human in the RevenueCat dashboard, add the App Store configuration for bundle id `com.logyourbody.app`, then switch production builds from the Test Store SDK key to the App Store SDK key.
