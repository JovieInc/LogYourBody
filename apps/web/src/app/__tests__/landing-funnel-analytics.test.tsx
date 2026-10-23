import { fireEvent, render, screen } from '@testing-library/react';
import { analytics } from '@/lib/analytics';
import { sanitizeAnalyticsProperties } from '@/lib/analytics-schema';
import { LANDING_FLAGS } from '@/lib/flags/landing';
import { readEditorialHomepageRollout } from '@/lib/flags/publicLanding.server';
import HomePage from '../page';
import IOSDownloadPage from '../download/ios/page';
import { MinimalWaitlistLanding } from '../MinimalWaitlistLanding';
import { LegacyMinimalWaitlistLanding } from '../LegacyMinimalWaitlistLanding';
import { waitlistLandingCopy } from '../waitlist-copy';

jest.mock('@/lib/analytics', () => ({ analytics: { track: jest.fn() } }));
jest.mock('@/lib/flags/landing', () => ({
  LANDING_FLAGS: { ART_DIRECTION_V2_ENABLED: false, APP_STORE_LIVE: false },
}));
jest.mock('@/lib/flags/publicLanding.server', () => ({ readEditorialHomepageRollout: jest.fn() }));

const track = jest.mocked(analytics.track);
const originalFetch = global.fetch;

beforeEach(() => {
  jest.clearAllMocks();
  global.fetch = jest.fn().mockResolvedValue({
    ok: true,
    status: 202,
    json: async () => ({ success: true }),
  });
  window.history.replaceState({}, '', '/?utm_source=Instagram&email=private@example.com&weight=80');
  (LANDING_FLAGS as { ART_DIRECTION_V2_ENABLED: boolean }).ART_DIRECTION_V2_ENABLED = false;
  jest.mocked(readEditorialHomepageRollout).mockResolvedValue(false);
});

afterEach(() => {
  global.fetch = originalFetch;
});

it.each([
  ['homepage', HomePage, 'launch_landing_v1', 'waitlist_launch'],
  ['iOS download', IOSDownloadPage, 'ios_download_v1', 'waitlist_launch'],
  ['minimal', MinimalWaitlistLanding, 'minimal_waitlist_v1', 'waitlist_minimal'],
  [
    'legacy minimal',
    LegacyMinimalWaitlistLanding,
    'legacy_minimal_waitlist_v1',
    'waitlist_minimal',
  ],
  [
    'editorial homepage',
    async () => {
      (LANDING_FLAGS as { ART_DIRECTION_V2_ENABLED: boolean }).ART_DIRECTION_V2_ENABLED = true;
      jest.mocked(readEditorialHomepageRollout).mockResolvedValue(true);
      return HomePage();
    },
    'editorial_landing_v1',
    'waitlist_editorial_v2',
  ],
] as const)(
  'attributes the complete %s funnel to the rendered landing',
  async (_name, page, landing_id, variant) => {
    render(await page());
    const email = screen.getByRole('textbox', { name: 'Email' });
    fireEvent.focus(email);
    fireEvent.blur(email);
    fireEvent.focus(email);
    fireEvent.change(email, { target: { value: 'private@example.com' } });
    fireEvent.click(screen.getByRole('button', { name: waitlistLandingCopy.submitLabel }));
    await screen.findByText(waitlistLandingCopy.successMessage);

    const properties = { landing_id, variant, campaign: 'instagram' };
    expect(track.mock.calls).toEqual([
      ['web_landing_viewed', properties],
      ['web_waitlist_started', properties],
      ['web_waitlist_submit_attempted', properties],
      ['web_waitlist_submitted', properties],
      ['web_waitlist_submit_result', { ...properties, outcome: 'accepted' }],
    ]);
    for (const [event, metadata] of track.mock.calls) {
      expect(sanitizeAnalyticsProperties(event, metadata)).toEqual(metadata);
    }
    expect(JSON.stringify(track.mock.calls)).not.toMatch(/private@example.com|weight|80/);
  },
);
