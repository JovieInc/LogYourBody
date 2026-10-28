import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { analytics } from '@/lib/analytics';
import { WaitlistForm } from '../WaitlistForm';
import { waitlistLandingCopy } from '../waitlist-copy';

jest.mock('@/lib/analytics', () => ({
  analytics: { track: jest.fn() },
}));

const landing = { landingId: 'launch_waitlist_v1', variant: 'waitlist_launch' } as const;
const outcomeAttribution = {
  landing_id: 'launch_waitlist_v1',
  variant: 'waitlist_launch',
  campaign: 'other',
};
const track = analytics.track as jest.MockedFunction<typeof analytics.track>;
const fetchMock = jest.fn();

describe('WaitlistForm', () => {
  beforeEach(() => {
    jest.clearAllMocks();
    window.history.replaceState({}, '', '/?utm_source=Test_Campaign');
    global.fetch = fetchMock;
  });

  afterEach(() => {
    delete (global as { fetch?: typeof fetch }).fetch;
  });

  it('records the funnel without sending email to analytics', async () => {
    fetchMock.mockResolvedValueOnce({
      ok: true,
      status: 202,
      json: async () => ({ success: true }),
    });
    render(<WaitlistForm {...landing} />);

    const email = screen.getByRole('textbox', { name: 'Email' });
    fireEvent.focus(email);
    fireEvent.change(email, { target: { value: 'person@example.com' } });
    fireEvent.click(screen.getByRole('button', { name: 'Request early access' }));

    await screen.findByText(waitlistLandingCopy.successMessage);
    expect(fetchMock).toHaveBeenCalledWith(
      '/api/waitlist',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({
          email: 'person@example.com',
          source: 'landing:minimal:other',
          website: '',
        }),
      }),
    );
    expect(track).toHaveBeenCalledWith(
      'web_waitlist_submit_result',
      expect.objectContaining({ outcome: 'accepted' }),
    );
    for (const event of [
      'web_landing_viewed',
      'web_waitlist_started',
      'web_waitlist_submit_attempted',
      'web_waitlist_submitted',
      'web_waitlist_submit_result',
    ]) {
      expect(track).toHaveBeenCalledWith(
        event,
        expect.objectContaining({
          landing_id: 'launch_waitlist_v1',
          variant: 'waitlist_launch',
          campaign: 'other',
        }),
      );
    }
    expect(JSON.stringify(track.mock.calls)).not.toContain('minimal_waitlist_v1');
    expect(JSON.stringify(track.mock.calls)).not.toContain('person@example.com');
    expect(JSON.stringify(track.mock.calls)).not.toContain('test_campaign');
  });

  it('announces invalid email without making a request', async () => {
    render(<WaitlistForm {...landing} />);
    fireEvent.click(screen.getByRole('button', { name: 'Request early access' }));

    expect(await screen.findByRole('alert')).toHaveTextContent('Enter a valid email address.');
    expect(fetchMock).not.toHaveBeenCalled();
    await waitFor(() =>
      expect(track).toHaveBeenCalledWith('web_waitlist_submit_result', {
        ...outcomeAttribution,
        outcome: 'invalid',
      }),
    );
  });

  it('returns server-side validation feedback to an editable form', async () => {
    fetchMock.mockResolvedValueOnce({
      ok: false,
      status: 400,
      json: async () => ({ success: false }),
    });
    render(<WaitlistForm {...landing} />);

    fireEvent.change(screen.getByRole('textbox', { name: 'Email' }), {
      target: { value: 'invalid@example.com' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Request early access' }));

    expect(await screen.findByRole('alert')).toHaveTextContent('Enter a valid email address.');
    expect(screen.getByRole('button', { name: 'Request early access' })).toBeEnabled();
    expect(track).toHaveBeenCalledWith('web_waitlist_submit_result', {
      ...outcomeAttribution,
      outcome: 'invalid',
    });
  });

  it('announces a rate limit without exposing implementation details', async () => {
    fetchMock.mockResolvedValueOnce({
      ok: false,
      status: 429,
      json: async () => ({ success: false }),
    });
    render(<WaitlistForm {...landing} />);

    fireEvent.change(screen.getByRole('textbox', { name: 'Email' }), {
      target: { value: 'person@example.com' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Request early access' }));

    expect(await screen.findByText(waitlistLandingCopy.errorMessage)).toHaveAttribute(
      'role',
      'status',
    );
    expect(track).toHaveBeenCalledWith('web_waitlist_submit_result', {
      ...outcomeAttribution,
      outcome: 'rate_limited',
    });
  });

  it('announces a recoverable error when the request fails', async () => {
    fetchMock.mockRejectedValueOnce(new Error('offline'));
    render(<WaitlistForm {...landing} />);

    fireEvent.change(screen.getByRole('textbox', { name: 'Email' }), {
      target: { value: 'person@example.com' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Request early access' }));

    expect(await screen.findByText(waitlistLandingCopy.errorMessage)).toHaveAttribute(
      'role',
      'status',
    );
    expect(track).toHaveBeenCalledWith('web_waitlist_submit_result', {
      ...outcomeAttribution,
      outcome: 'server_error',
    });
  });

  it('reports the landing that renders the form instead of a shared default', () => {
    render(<WaitlistForm landingId="ios_download_v1" variant="waitlist_editorial" />);

    expect(track).toHaveBeenCalledWith(
      'web_landing_viewed',
      expect.objectContaining({ landing_id: 'ios_download_v1', variant: 'waitlist_editorial' }),
    );
    expect(JSON.stringify(track.mock.calls)).not.toContain('minimal_waitlist_v1');
  });
});
