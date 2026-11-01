# Signing certificate and profile expiry

The daily check in [`.github/workflows/signing-expiry.yml`](../../.github/workflows/signing-expiry.yml) reports how long the signing material used for TestFlight and App Store builds will keep working. It is read-only. It does not install, create, revoke, rotate, or nuke certificates or profiles, and it does not print key IDs, private keys, passwords, or certificate bytes.

Dispatch the same workflow manually to read again. `dry_run` prints the report and skips Linear.

## What it reads

App Store Connect `GET` only:

- Required bundle IDs from `app_identifier` in [`apps/ios/fastlane/Matchfile`](../../apps/ios/fastlane/Matchfile). That list is the source of truth. The readonly match workaround in `Fastfile.release` (LYB-310) can omit an identifier for one archive; it does not remove that identifier from this check.
- For each required bundle ID, the active App Store profile (`IOS_APP_STORE`), the days left on that profile, and the distribution certificate type embedded in it. When several active profiles exist for one bundle ID, the report uses the one with the most days left. A required ID with no active profile is `missing`.
- The distribution certificate embedded in those profiles (`IOS_DISTRIBUTION` or `DISTRIBUTION`), with its days left. Other valid distribution certificates are `unused`. Already-expired certificates that no required profile embeds are omitted. They do not hide an in-use certificate, and they do not change the warn or escalate level.
- The App Store Connect API key used by release automation. Apple team API keys do not expire. A successful read reports `asc api key: no expiration date`. A rejected read is treated as expired.

Report lines name a profile by bundle ID and a certificate by type. They do not include serial numbers, key IDs, certificate bytes, or profile bytes. A profile line looks like `com.logyourbody.app IOS_APP_STORE: 180 days (IOS_DISTRIBUTION, 400 days)`: the profile expires in 180 days and embeds an `IOS_DISTRIBUTION` certificate that expires in 400 days.

## When it files

One Linear issue on team LYB, fingerprint `remediation:signing-expiry`.

- Under 30 days on a required profile or an in-use distribution certificate: open or reopen that issue at High priority.
- Under 7 days, or a missing or unreadable required profile, certificate, or API key: the same issue, Urgent priority, with `ESCALATED` in the description and comment. A required bundle ID with no active App Store profile is missing and escalates.
- Unused distribution certificates do not open, raise, or keep that issue open.
- 30 days or more on every required profile and in-use certificate, and an authenticated key with no expiration date: resolve the open issue if one exists. Do not open a new one.

30 days exactly is not under 30. 7 days exactly stays High and does not escalate. The issue body contains only the asset kind and the day count, plus this runbook path.

## Pull request check

The **Release signing provisioned** job in [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) runs when a pull request changes `apps/ios/fastlane/`, a `project.pbxproj`, or an entitlements file. `CI Summary` requires it for those pulls. It reads the bundle IDs that `setup_provisioning` passes to match for `type:appstore` and `readonly:true` in [`apps/ios/fastlane/Fastfile.release`](../../apps/ios/fastlane/Fastfile.release). If that lane omits `app_identifier`, the Matchfile list is the fallback. The check then GETs App Store Connect. It fails when a required bundle ID is not registered, has no active App Store profile (`IOS_APP_STORE`), or that profile does not allow a capability the target entitlements need. A profile value of `*` or a prefix ending in `*` allows the more specific value the target claims (TN3125). Associated Domains is stored as `*` in the profile while the target lists each service and domain. A missing key still fails, and a boolean capability still has to be true.

A failure is a provisioning step for Tim. Use step 2 below from a machine that already has the Match and App Store Connect secrets. The check does not create profiles. Its output has no key IDs, bundle IDs, team IDs, or profile bytes.

A fork pull request has no App Store Connect credentials. That job finishes neutral and says it did not pass. A pull request from this repository fails closed when those credentials are missing.

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

### 3. Nuke only after refresh cannot

[`.github/workflows/regenerate-certificates.yml`](../../.github/workflows/regenerate-certificates.yml) is manual. It runs `match_nuke` and deletes the certificates and profiles in the Match repository. Dispatch it only after the refresh above cannot produce a usable distribution certificate, and only by typing `NUKE-AND-REGENERATE` into the confirm input. There is no schedule. The expiry check never starts this workflow.

Related: LYB-141, LYB-332, LYB-285, LYB-310, LYB-74, LYB-65.
