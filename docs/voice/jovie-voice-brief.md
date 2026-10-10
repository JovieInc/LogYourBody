# Coach voice brief

## Selected voice

Jovie v1 uses ElevenLabs voice ID `A4j35F5T4XsPMeXd06Pm`, promoted from the round-four B-1 preview after explicit owner selection. Do not create or promote another voice without a new selection. Runtime TTS prefers `eleven_flash_v2_5` for gym latency; multilingual v2 was also used for a transport smoke check.

`LYB_VOICE_ID` is configured in the LYB Vercel Preview and Production environments. Keep `LYB_VOICE_ENABLED=false` and the Statsig gate `hypertrophy_coach_voice_v1` off until an explicit rollout. The gate and the ElevenLabs provider also require `LYB_VOICE_ALLOWLIST` (Jovie subject ids or emails). That list defaults empty, so voice stays off for every account until the owner's subject or email is set in Doppler or Vercel. Do not commit the identifier.

## Voice and spoken-copy direction

The voice should feel cooler, more confident, and unfazed; clear and concise, with a subtle intimate quality that is not sexual. Keep the delivery direct, useful, human, and calm under pressure. Avoid grandiose, vague, perky, or announcer-like delivery, and do not imitate a specific speaker.

Spoken replies should be one short, direct imperative line, usually about 12 words or fewer. Avoid filler and explanations. A question from the user permits a longer answer when needed to answer it. Preferred example: “Stop here. Rack it. Two minutes.”

## Selection rounds

- Round 1: all nine initial candidates were rejected. Their preview files are excluded from the repository.
- Round 2: a cooler, flatter, composed direction was selected as the starting point; the requested refinement was brighter, lighter, and slightly playful.
- Round 3: two clearer candidate directions were the right fit; the next request was a tighter delivery.
- Round 4: candidate B-1 was selected and promoted as Jovie v1.
- Round 5: added-intimacy variants were rejected as worse. Do not continue that branch of exploration now.

Rejected preview IDs and audio files are intentionally not stored in the public repository. The selected voice's local smoke clips remain outside the repository.

## Credential handling

The ElevenLabs API key is configured as a sensitive Vercel environment variable for Preview and Production. For authorized local CLI work, retrieve only this existing key from Doppler and never print or commit it. New secrets follow the [secrets policy](../engineering/secrets-policy.md): Doppler stays the secrets manager, and new values are added directly to GitHub Actions and Vercel.

```sh
export ELEVENLABS_API_KEY="$(doppler secrets get ELEVENLABS_API_KEY --project jovie-web --config prd_agent_ops --plain)"
elevenlabs-pp-cli doctor --agent
```
