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
- The RevenueCat MCP endpoint in `.cursor/mcp.json` points at `localhost:49797`, but no local server was listening there during Codex provisioning. RevenueCat was configured through the v2 REST API instead.

## AgentMail

- AgentMail CLI is installed through pnpm global tooling.
- pnpm global bin is configured in `~/.zshrc` as `PNPM_HOME=/Users/timwhite/Library/pnpm`.
- Agent inbox created: `logyourbody-codex@agentmail.to`.
- AgentMail API credentials are stored outside the repo at:
  `/Users/timwhite/.codex/secrets/logyourbody-revenuecat-agentmail.env`
- AgentMail full verification is still pending because the OTP was sent to `t@timwhite.co`, which is not the Gmail mailbox available to Codex in this session.
- The unverified AgentMail inbox can receive mail and was used to complete RevenueCat email confirmation.

## RevenueCat

- Project name: `LogYourBody`.
- Dashboard/project slug: `2385165b`.
- API project id: `proj2385165b`.
- App Store app id: `app5fa54db3c0`.
- App Store bundle id: `com.logyourbody.app`.
- App Store API key configuration: configured.
- App Store in-app purchase key configuration: configured.
- Local RevenueCat credentials are stored outside the repo at:
  `/Users/timwhite/.codex/secrets/logyourbody-revenuecat-agentmail.env`
- Production App Store SDK key is stored in the private env file and local ignored iOS config.

## Current Offering Verification

The RevenueCat App Store offering is configured and verified.

- Current offering: `default`.
- Entitlement lookup key: `Premium`.
- Entitlement id: `entled3b1a2e7a`.
- Offering id: `ofrng86fde23d98`.
- Monthly product:
  `com.logyourbody.app.pro1.monthly.3daytrial`.
- Annual product:
  `com.logyourbody.app.pro1.annual.3daytrial`, duration `P1Y`.
- Packages returned by the SDK offering endpoint:
  `$rc_monthly` and `$rc_annual`.
- The SDK offering endpoint must be called with `X-Platform: ios`; without it, the generic offering response can show empty packages even when the iOS offering is valid.

Verified with:

```bash
REVENUE_CAT_PUBLIC_KEY=<app-store-sdk-key> apps/ios/Scripts/verify_revenuecat_offerings.sh
```

Result:

```text
Verified RevenueCat current offering default includes $rc_annual:com.logyourbody.app.pro1.annual.3daytrial, $rc_monthly:com.logyourbody.app.pro1.monthly.3daytrial.
```

## Local iOS Config

The ignored local file `apps/ios/LogYourBody/Config.xcconfig` now uses the production App Store SDK key for `REVENUE_CAT_API_KEY`, so local builds can fetch the verified iOS offering.

## GitHub Secrets

The GitHub `Production` environment has been updated so the iOS release workflow uses the verified App Store SDK key:

- `REVENUE_CAT_PUBLIC_KEY`
- `REVENUE_CAT_API_KEY`

## Remaining Release Blocker

RevenueCat is now configured for the App Store app and the iOS offering preflight passes against the production App Store SDK key.

The remaining gates are outside RevenueCat configuration:

- App Store Connect products are `READY_TO_SUBMIT` and must be approved/available for sandbox/live purchase.
- Run a real sandbox purchase and restore on a TestFlight or App Store build.
- Merge the paid MVP PR after human review and green checks.
