import { waitlistLandingCopy } from '../waitlist-copy';

const BANNED_MARKETING_TERMS = [
  /\blorem\s+ipsum\b/i,
  /\bfake\s+data\b/i,
  /\bplaceholder\b/i,
  /\bjohn\s+doe\b/i,
  /\btest\s+user\b/i,
  /\b10,000\+\b/,
  /\b93%\b/,
];

describe('waitlist landing copy lint', () => {
  it('keeps public waitlist copy free of banned placeholder or unverified claims', () => {
    const copyBlob = Object.values(waitlistLandingCopy).join('\n');

    for (const pattern of BANNED_MARKETING_TERMS) {
      expect(copyBlob).not.toMatch(pattern);
    }
  });
});
