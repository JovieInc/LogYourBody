# Stripe Projects Reprovisioning Experiment

Date: 2026-06-02

Status: Not run locally.

## Commands Attempted

```bash
command -v stripe
stripe --version
```

Result:

- `command -v stripe` returned no path.
- `stripe --version` failed with `command not found: stripe`.

No Clerk, Supabase, AgentMail, Stripe vault, state, or credential resources were created.

## Intended Experiment

Use Stripe Projects only for isolated dev reprovisioning experiments. Do not make production depend on generated Projects resources unless the setup is explicit, reproducible, and reviewed.

Intended resources, if the local toolchain supports them:

- Clerk dev/test project or app.
- Supabase dev project.
- Optional AgentMail mailbox/domain for email-code verification tests.

## Credential Handling

Generated credentials must be copied only into local gitignored files:

- `apps/ios/LogYourBody/Config-Development.xcconfig`
- local provider vault/state files documented by the provisioning tool

Never commit:

- Generated vaults or state files.
- Clerk secret keys.
- Supabase service role keys.
- Real `.xcconfig` files.
- `.env` files with provider credentials.

## Rollback and Deprovision

If the experiment is run later:

1. Record every created provider resource id.
2. Disable or delete test Clerk app/project.
3. Pause or delete test Supabase project.
4. Disable AgentMail test routing if created.
5. Delete generated local vault/state files after extracting any needed non-secret notes.
6. Revert `Config.xcconfig` to the reviewed dev include.

## Recommendation

Do not use Stripe Projects for production provider setup in this PR. It can be useful for repeatable dev resource creation once the CLI/tooling is installed and the exact commands are reviewed.
