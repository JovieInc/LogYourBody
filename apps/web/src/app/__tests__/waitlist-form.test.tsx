import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { analytics } from '@/lib/analytics';
import { WaitlistForm } from '../WaitlistForm';

jest.mock('@/lib/analytics', () => ({
  analytics: { track: jest.fn() },
}));

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
    render(<WaitlistForm />);

    const email = screen.getByRole('textbox', { name: 'Email' });
    fireEvent.focus(email);
    fireEvent.change(email, { target: { value: 'person@example.com' } });
    fireEvent.click(screen.getByRole('button', { name: 'Request early access' }));

    await screen.findByText(/TestFlight spot opens/i);
    expect(fetchMock).toHaveBeenCalledWith(
      '/api/waitlist',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({
          email: 'person@example.com',
          source: 'landing:minimal:test_campaign',
          website: '',
        }),
      }),
    );
    expect(track).toHaveBeenCalledWith(
      'web_waitlist_submit_result',
      expect.objectContaining({ outcome: 'accepted' }),
    );
    expect(JSON.stringify(track.mock.calls)).not.toContain('person@example.com');
  });

  it('announces invalid email without making a request', async () => {
    render(<WaitlistForm />);
    fireEvent.click(screen.getByRole('button', { name: 'Request early access' }));

    expect(await screen.findByRole('alert')).toHaveTextContent('Enter a valid email address.');
    expect(fetchMock).not.toHaveBeenCalled();
    await waitFor(() =>
      expect(track).toHaveBeenCalledWith('web_waitlist_submit_result', { outcome: 'invalid' }),
    );
  });
});
