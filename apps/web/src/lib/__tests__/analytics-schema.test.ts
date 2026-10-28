import {
  isAnalyticsEvent,
  sanitizeAnalyticsPrincipal,
  sanitizeAnalyticsProperties,
  sanitizeAnalyticsTraits,
  waitlistCampaign,
} from '../analytics-schema';

describe('closed analytics schema', () => {
  it('rejects health values, contact data, content, identifiers, URLs, raw errors and unknown keys', () => {
    const unsafe = {
      campaign: 'weight_80kg',
      email: 'synthetic@example.com',
      name: 'Synthetic Person',
      weight: 80,
      body_fat: 20,
      photo_url: 'https://e/private-photo',
      transcript: 'private speech',
      exercise_name: 'private workout',
      error: 'database contains secret',
      access_token: 'synthetic-secret',
      user_id: 'synthetic-user',
      variant: 'waitlist_minimal',
      omitted: undefined,
    };
    expect(sanitizeAnalyticsProperties('web_waitlist_submitted', unsafe)).toEqual({
      variant: 'waitlist_minimal',
    });
    expect(sanitizeAnalyticsTraits({ ...unsafe, platform: 'web' })).toEqual({ platform: 'web' });
  });

  it('accepts only the values defined for that event', () => {
    expect(
      sanitizeAnalyticsProperties('web_waitlist_submit_result', {
        outcome: 'accepted',
        variant: 'waitlist_minimal',
      }),
    ).toEqual({ outcome: 'accepted' });
    expect(
      sanitizeAnalyticsProperties('web_waitlist_submit_result', { outcome: 'private error' }),
    ).toEqual({});
    expect(sanitizeAnalyticsTraits({ platform: 'synthetic@example.com' })).toEqual({});
  });

  it('rejects arbitrary event names and prototype keys', () => {
    expect(isAnalyticsEvent('synthetic@example.com')).toBe(false);
    expect(isAnalyticsEvent('__proto__')).toBe(false);
    expect(isAnalyticsEvent('constructor')).toBe(false);
    expect(
      sanitizeAnalyticsProperties('web_landing_viewed', JSON.parse('{"__proto__":"private"}')),
    ).toEqual({});
  });

  it('accepts an opaque principal and rejects contact, URL or token-shaped identifiers', () => {
    expect(sanitizeAnalyticsPrincipal('opaque-synthetic-principal')).toBe(
      'opaque-synthetic-principal',
    );
    for (const value of ['synthetic@example.com', 'https://e', 'Bearer secret', 'a.b.c']) {
      expect(sanitizeAnalyticsPrincipal(value)).toBeUndefined();
    }
  });

  it.each([
    [null, 'direct'],
    ['Instagram', 'instagram'],
    ['synthetic@example.com', 'other'],
    ['a'.repeat(500), 'other'],
    ['weight_80kg', 'other'],
  ])('maps campaign input %s to a closed code', (input, expected) => {
    expect(waitlistCampaign(input)).toBe(expected);
  });
});
