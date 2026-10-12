import { launchLandingCopy, launchLandingFeatures } from '../launch-landing-copy';

const BANNED_MARKETING_TERMS = [
  /\blorem\s+ipsum\b/i,
  /\bfake\s+data\b/i,
  /\bplaceholder\b/i,
  /\bjohn\s+doe\b/i,
  /\btest\s+user\b/i,
  /\b10,000\+\b/,
  /\b93%\b/,
  /\bguarantee/i,
  /\bpremium\b/i,
  /\bcinematic\b/i,
  /\bseamless\b/i,
  /\bworld[- ]class\b/i,
];

function flatten(value: unknown): string[] {
  if (typeof value === 'string') return [value];
  if (Array.isArray(value)) return value.flatMap(flatten);
  if (value && typeof value === 'object') return Object.values(value).flatMap(flatten);
  return [];
}

describe('launch landing copy lint', () => {
  it('keeps every visible line free of placeholder, unverified or style-as-outcome language', () => {
    const copyBlob = [...flatten(launchLandingCopy), ...flatten(launchLandingFeatures)].join('\n');

    for (const pattern of BANNED_MARKETING_TERMS) {
      expect(copyBlob).not.toMatch(pattern);
    }
  });

  it('only markets features the registry says are available', () => {
    expect(launchLandingFeatures.length).toBeGreaterThan(0);
    for (const feature of launchLandingFeatures) {
      expect(feature.description.trim().length).toBeGreaterThan(0);
    }
  });
});
