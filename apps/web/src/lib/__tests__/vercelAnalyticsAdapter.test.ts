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
});
