# Voice design brief

## Status

Voice generation is pending access to the configured provider credentials. No candidates or preview audio have been generated, no voice has been selected, and `LYB_VOICE_ID` remains `PLACEHOLDER_VOICE_ID`. Candidate IDs and preview paths will be recorded here only after the CLI returns them.

The installed `elevenlabs-pp-cli` is version 2026.7.1. Its unauthenticated model-list request resolved to an anonymous, nonexistent workspace. Both authorized Doppler configs (`jovie-web/prd_agent_ops` and `jovie-web/prd`) denied access to restricted secrets before the CLI started. No credential was read or printed.

## Original candidate prompts

These prompts describe distinct, original voices without imitating an existing speaker or recording. Each candidate should use the same short preview text: “Your next set is ready. Take a steady breath, then begin when you feel prepared.”

1. **Clear and measured:** An adult voice with a clear, natural speaking tone; warm but restrained; medium pitch; crisp consonants; even pacing; calm pauses; no announcer energy or exaggerated emotion.
   - State: not generated
   - Planned preview: `docs/voice/previews/candidate-1.mp3` (file absent)
   - `generated_voice_id`: not available
2. **Calm and neutral:** An adult voice with a grounded, neutral tone; lower-mid pitch; unhurried phrasing; soft but intelligible consonants; understated confidence; no theatrical delivery.
   - State: not generated
   - Planned preview: `docs/voice/previews/candidate-2.mp3` (file absent)
   - `generated_voice_id`: not available
3. **Bright and direct:** An adult voice with a slightly brighter mid-range tone; concise phrasing; clear articulation; supportive but not motivational; natural pauses; no exaggerated cheerfulness.
   - State: not generated
   - Planned preview: `docs/voice/previews/candidate-3.mp3` (file absent)
   - `generated_voice_id`: not available

## Generation commands

When the authorized key is readable, run one design request per prompt, save each CLI audio preview under `docs/voice/previews/`, and copy each returned `generated_voice_id` into the matching candidate above. Keep the adapter on the placeholder until a voice is explicitly selected.

```sh
doppler run --project jovie-web --config prd_agent_ops -- elevenlabs-pp-cli text-to-voice design --agent --voice-description '<candidate prompt>' --text 'Your next set is ready. Take a steady breath, then begin when you feel prepared.'
```
