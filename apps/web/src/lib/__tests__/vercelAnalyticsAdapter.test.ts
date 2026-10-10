import { track } from '@vercel/analytics';
import { createVercelAnalytics } from '../vercelAnalyticsAdapter';

jest.mock('@vercel/analytics', () => ({
  track: jest.fn(),
}));

describe('createVercelAnalytics', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('sends custom funnel events without undefined metadata', () => {
    createVercelAnalytics().track('web_waitlist_submitted', {
      landing_id: 'minimal_waitlist_v1',
      variant: 'waitlist_minimal',
      omitted: undefined,
    });

    expect(track).toHaveBeenCalledWith('web_waitlist_submitted', {
      landing_id: 'minimal_waitlist_v1',
      variant: 'waitlist_minimal',
    });
  });

  it('does not interrupt conversion when analytics throws', () => {
    (track as jest.Mock).mockImplementationOnce(() => {
      throw new Error('analytics unavailable');
    });

    expect(() => createVercelAnalytics().track('web_waitlist_submitted')).not.toThrow();
  });

  it('drops sensitive metadata and arbitrary event names at the adapter boundary', () => {
    const port = createVercelAnalytics();
    port.track('web_waitlist_submitted', {
      email: 'synthetic@example.com',
      weight: 80,
      campaign: 'private health text',
      photo_url: 'https://e/private',
      error: 'secret',
      variant: 'waitlist_minimal',
    });
    expect(track).toHaveBeenCalledWith('web_waitlist_submitted', { variant: 'waitlist_minimal' });
    port.track('synthetic@example.com');
    expect(track).toHaveBeenCalledTimes(1);
  });
});
