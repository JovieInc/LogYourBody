/** @jest-environment node */

import {
  HYPERTROPHY_COACH_VOICE_GATE,
  parseVoiceAllowlist,
  selectVoiceProvider,
  voiceCoachAccess,
} from '../access';
import type { VoiceProvider } from '../provider';

const elevenlabs: VoiceProvider = { tts: jest.fn(async () => new ReadableStream()) };
const fishAudio: VoiceProvider = { tts: jest.fn(async () => new ReadableStream()) };
const providers = { elevenlabs, 'fish-audio': fishAudio };

describe('hypertrophy coach voice allowlist', () => {
  it('keeps the existing default-off gate name', () => {
    expect(HYPERTROPHY_COACH_VOICE_GATE).toBe('hypertrophy_coach_voice_v1');
  });

  it('defaults to an empty allowlist and denies every account', () => {
    expect(parseVoiceAllowlist(undefined).size).toBe(0);
    expect(parseVoiceAllowlist('').size).toBe(0);
    expect(parseVoiceAllowlist(' , ; ').size).toBe(0);
    expect(
      voiceCoachAccess(
        { sub: 'owner-subject', email: 'tim@timwhite.dev' },
        { LYB_VOICE_ENABLED: 'true' },
      ),
    ).toBe('forbidden');
  });

  it('matches a subject exactly and an email case-insensitively', () => {
    const allowlist = parseVoiceAllowlist(' owner-subject, Tim@Example.com ');
    expect(
      voiceCoachAccess(
        { sub: 'owner-subject', email: 'other@example.com' },
        { LYB_VOICE_ENABLED: 'true', LYB_VOICE_ALLOWLIST: ' owner-subject, Tim@Example.com ' },
      ),
    ).toBe('ok');
    expect(
      voiceCoachAccess(
        { sub: 'someone-else', email: 'tim@example.com' },
        { LYB_VOICE_ENABLED: 'true', LYB_VOICE_ALLOWLIST: [...allowlist].join(',') },
      ),
    ).toBe('ok');
    expect(
      voiceCoachAccess(
        { sub: 'Owner-Subject', email: 'nope@example.com' },
        { LYB_VOICE_ENABLED: 'true', LYB_VOICE_ALLOWLIST: 'owner-subject' },
      ),
    ).toBe('forbidden');
  });

  it('keeps an allowlisted account off until the gate is exactly true', () => {
    expect(
      voiceCoachAccess(
        { sub: 'owner-subject' },
        { LYB_VOICE_ENABLED: 'false', LYB_VOICE_ALLOWLIST: 'owner-subject' },
      ),
    ).toBe('disabled');
    expect(
      voiceCoachAccess(
        { sub: 'owner-subject' },
        { LYB_VOICE_ENABLED: 'TRUE', LYB_VOICE_ALLOWLIST: 'owner-subject' },
      ),
    ).toBe('disabled');
  });

  it('withholds ElevenLabs unless the actor is allowlisted', () => {
    const allowlist = parseVoiceAllowlist('owner-subject');
    expect(
      selectVoiceProvider({
        providers,
        providerId: 'elevenlabs',
        actor: { sub: 'someone-else', email: 'tim@timwhite.dev' },
        allowlist,
      }),
    ).toBeNull();
    expect(
      selectVoiceProvider({
        providers,
        providerId: 'elevenlabs',
        actor: { sub: 'owner-subject' },
        allowlist,
      }),
    ).toBe(elevenlabs);
    expect(
      selectVoiceProvider({
        providers,
        providerId: 'fish-audio',
        actor: { sub: 'someone-else' },
        allowlist,
      }),
    ).toBeNull();
    expect(elevenlabs.tts).not.toHaveBeenCalled();
    expect(fishAudio.tts).not.toHaveBeenCalled();
  });
});
