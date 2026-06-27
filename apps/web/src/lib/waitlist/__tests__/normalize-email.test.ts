import { normalizeWaitlistEmail } from '../normalize-email';

describe('normalizeWaitlistEmail', () => {
  it('lowercases and trims valid emails', () => {
    expect(normalizeWaitlistEmail('  User@Example.COM ')).toBe('user@example.com');
  });

  it('rejects invalid addresses', () => {
    expect(normalizeWaitlistEmail('not-an-email')).toBeNull();
    expect(normalizeWaitlistEmail('')).toBeNull();
  });
});
