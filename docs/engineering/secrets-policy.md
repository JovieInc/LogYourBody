# Secrets policy

Doppler remains the secrets manager for LogYourBody. This policy records how new secrets are added. It does not change Doppler projects, configs, syncs, or billing.

Related: [LYB-95](https://linear.app/jovie/issue/LYB-95). Capacity work on the existing Doppler to GitHub sync stays in [JOV-7237](https://linear.app/jovie/issue/JOV-7237).

## Stores

- **Doppler** is the secrets manager. Existing projects, configs, and syncs stay as they are. Local reads that already use Doppler stay valid, including `pnpm setup:gbrain` against `jovie-web/dev` and the authorized ElevenLabs CLI retrieval in the [voice brief](../voice/jovie-voice-brief.md).
- **GitHub Actions secrets** are where CI and CD credentials are stored.
- **Vercel environment variables** are where web Preview and Production runtime configuration is stored.
- **iOS** local configuration stays in gitignored `.xcconfig` files.

## Adding a new secret

New secrets are written directly to the GitHub Actions destination and the Vercel destination that need them.

1. Tim supplies the value through a secure input. The value does not go in chat, Linear, a pull request, a commit, or a log.
2. Grok Bot adds that value to GitHub Actions and to Vercel.
3. Record the secret name and the destination. Do not record the value.

Doppler sync changes and Doppler billing stay with Tim. Agents leave Doppler syncs and the Doppler plan unchanged.

## Handling rules

- Never commit secrets or API keys.
- Never print secret values.
- Never delete or rotate a production secret unless Tim has given that instruction on the owning issue.
