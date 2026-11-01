# Signing certificate and profile expiry

The daily check in [`.github/workflows/signing-expiry.yml`](../../.github/workflows/signing-expiry.yml) reports how long the signing material used for TestFlight and App Store builds will keep working. It is read-only. It does not install, create, revoke, rotate, or nuke certificates or profiles, and it does not print key IDs, private keys, passwords, or certificate bytes.

Dispatch the same workflow manually to read again. `dry_run` prints the report and skips Linear.

## What it reads

App Store Connect `GET` only:

- Apple Distribution and legacy iOS Distribution certificates (`IOS_DISTRIBUTION`, `DISTRIBUTION`). The report uses the soonest certificate that is not yet expired. Already-expired leftovers do not hide a newer valid certificate. If every distribution certificate is expired or missing, the report says so.
- Active App Store provisioning profiles (`IOS_APP_STORE`) for `com.logyourbody.app` and its extensions. Each profile gets its own days count.
- The App Store Connect API key used by release automation. Apple team API keys do not expire. A successful read reports `asc api key: no expiration date`. A rejected read is treated as expired.

## When it files

One Linear issue on team LYB, fingerprint `remediation:signing-expiry`.

- Under 30 days: open or reopen that issue at High priority.
- Under 7 days, or a missing or unreadable asset: the same issue, Urgent priority, with `ESCALATED` in the description and comment.
- 30 days or more, and an authenticated key with no expiration date: resolve the open issue if one exists. Do not open a new one.

30 days exactly is not under 30. 7 days exactly stays High and does not escalate. The issue body contains only the asset kind and the day count, plus this runbook path.

## Renew before nuke

Stop at the first step that leaves a usable distribution certificate and App Store profile. Run these from a machine that already has the Match and App Store Connect secrets. Do not put those values in the command line, the shell history you paste into chat, or the Linear issue.

### 1. Confirm

Re-run **Signing expiry check**, or from `apps/ios`:

```sh
bundle exec fastlane setup_provisioning type:appstore readonly:true
```

This downloads the current Match material. It does not create or revoke anything.

### 2. Refresh with match

Use this when a profile is near expiry and the distribution certificate is still valid. Also use it when the certificate itself is expired and Apple can issue another distribution certificate without revoking the current one.

```sh
bundle exec fastlane setup_provisioning type:appstore readonly:false force:false
```

`force:false` is required. `force:true` revokes the current distribution certificate. Do not set `MATCH_READONLY=false` on release jobs. Do not run `match_nuke`, the `nuke_all_certs` lane, or `regenerate_profiles`.

This refresh can create a certificate. Write mode asks Match for an **Apple Distribution** certificate (portal type `DISTRIBUTION`, via `generate_apple_certs`). Release lanes sign with `code_sign_identity: "Apple Distribution"`, and the Xcode project sets `CODE_SIGN_IDENTITY` to the same identity. Step 1 only installs the certificate already stored in Match. `scripts/ios/test_distribution_cert_identity.rb` fails when a write-mode distribution sync would create a different identity.

Before the next release, confirm the installed distribution identity on the machine that ran the refresh:

```sh
security find-identity -v -p codesigning
```

Continue only when the distribution line Match installed reads `Apple Distribution:`. Match prints that common name in its summary table. A legacy iOS Distribution certificate (`iPhone Distribution:`) will not satisfy the release lanes. Do not archive until the `Apple Distribution:` identity is the one installed.

If Match reports that the stored certificate is not valid, this refresh did not create a replacement. Do not archive. Go to step 3 only when this refresh cannot leave a usable Apple Distribution certificate.

### 3. Nuke only after refresh cannot

[`.github/workflows/regenerate-certificates.yml`](../../.github/workflows/regenerate-certificates.yml) is manual. It runs `match_nuke` and deletes the certificates and profiles in the Match repository. Dispatch it only after the refresh above cannot produce a usable distribution certificate, and only by typing `NUKE-AND-REGENERATE` into the confirm input. There is no schedule. The expiry check never starts this workflow.

Related: LYB-141, LYB-74, LYB-65.
