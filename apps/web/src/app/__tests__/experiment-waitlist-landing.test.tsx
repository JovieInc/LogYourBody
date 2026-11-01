import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import type { HTMLAttributes, JSX } from 'react';
import { ExperimentWaitlistLanding } from '../ExperimentWaitlistLanding';
import { resolveLandingVariant } from '@/lib/marketing/landing-registry';
import { analytics } from '@/lib/analytics';

jest.mock('@/lib/analytics', () => ({
  analytics: {
    track: jest.fn(),
  },
}));

jest.mock('framer-motion', () => ({
  motion: new Proxy(
    {},
    {
      get: (_target, key: string) => {
        const MockMotion = ({
          animate: _animate,
          initial: _initial,
          transition: _transition,
          ...props
        }: HTMLAttributes<HTMLElement> & {
          animate?: unknown;
          initial?: unknown;
          transition?: unknown;
        }) => {
          const Element = key as keyof JSX.IntrinsicElements;
          return <Element {...props} />;
        };
        return MockMotion;
      },
    },
  ),
  useReducedMotion: () => true,
}));

describe('ExperimentWaitlistLanding', () => {
  const originalFetch = global.fetch;

  afterEach(() => {
    global.fetch = originalFetch;
    jest.clearAllMocks();
  });

  it('renders one conversion path with legal navigation and no unverified social proof', () => {
    render(
      <ExperimentWaitlistLanding
        variant={resolveLandingVariant({ audience: 'women', goal: 'recomposition' })}
        assignmentSource="campaign"
      />,
    );

    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(
      'Your body-composition goal, planned around your next date.',
    );
    expect(screen.getByRole('textbox', { name: 'Email' })).toBeInTheDocument();
    expect(screen.getAllByRole('button', { name: 'Get early access' })).toHaveLength(1);
    expect(screen.getAllByRole('navigation')).toHaveLength(1);
    expect(screen.getByRole('navigation', { name: 'Legal' })).toBeVisible();
    expect(screen.getByRole('link', { name: 'Consumer health data' })).toHaveAttribute(
      'href',
      '/consumer-health-data',
    );
    expect(
      screen.queryByText(/testimonial|app store rating|people tracking/i),
    ).not.toBeInTheDocument();
    expect(screen.getByTestId('landing-product-proof')).toBeInTheDocument();
  });

  it('keeps the field and CTA pill shaped and inline at the desktop breakpoint', () => {
    render(
      <ExperimentWaitlistLanding
        variant={resolveLandingVariant({ audience: 'men', goal: 'recomposition' })}
        assignmentSource="experiment"
      />,
    );

    const form = screen.getByTestId('landing-capture-form');
    const input = screen.getByRole('textbox', { name: 'Email' });
    const button = screen.getByRole('button', { name: 'Get early access' });
    expect(form).toHaveClass('lg:grid-cols-[minmax(0,1fr)_auto]');
    expect(input).toHaveClass('rounded-full');
    expect(button).toHaveClass('rounded-full');
  });

  it('submits campaign and variant attribution with the waitlist request', async () => {
    global.fetch = jest.fn().mockResolvedValue({
      ok: true,
      status: 201,
      json: async () => ({ success: true, status: 'created' }),
    }) as jest.Mock;
    render(
      <ExperimentWaitlistLanding
        variant={resolveLandingVariant({ audience: 'women', goal: 'fat-loss' })}
        assignmentSource="campaign"
      />,
    );

    fireEvent.change(screen.getByRole('textbox', { name: 'Email' }), {
      target: { value: 'founder@example.com' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Get early access' }));

    await waitFor(() => expect(global.fetch).toHaveBeenCalledTimes(1));
    expect(global.fetch).toHaveBeenCalledWith(
      '/api/waitlist',
      expect.objectContaining({
        method: 'POST',
        body: JSON.stringify({
          email: 'founder@example.com',
          source: 'landing:v2:women:fat-loss:campaign',
        }),
      }),
    );
    expect(
      await screen.findByText(
        "You're on the early-access list. We'll email you when your invite is ready.",
      ),
    ).toBeInTheDocument();
  });

  it('shows validation feedback without attempting a request', () => {
    global.fetch = jest.fn() as jest.Mock;
    render(
      <ExperimentWaitlistLanding
        variant={resolveLandingVariant({})}
        assignmentSource="experiment"
      />,
    );

    fireEvent.click(screen.getByRole('button', { name: 'Get early access' }));
    expect(screen.getByRole('alert')).toHaveTextContent('Enter a valid email address.');
    expect(screen.getByRole('textbox', { name: 'Email' })).toHaveFocus();
    expect(global.fetch).not.toHaveBeenCalled();
    expect(analytics.track).toHaveBeenCalledWith(
      'web_waitlist_submit_result',
      expect.objectContaining({ outcome: 'invalid', variant: 'waitlist_editorial_v2' }),
    );
  });

  it.each([
    [200, { success: true }, 'accepted'],
    [200, { success: true, status: 'existing' }, 'accepted'],
    [400, { success: false }, 'invalid'],
    [429, { success: false }, 'rate_limited'],
    [500, { success: false }, 'server_error'],
  ])(
    'records bounded funnel outcomes for HTTP %s without leaking registration status',
    async (status, payload, outcome) => {
      global.fetch = jest.fn().mockResolvedValue({
        ok: status === 200,
        status,
        json: async () => payload,
      });
      render(
        <ExperimentWaitlistLanding
          variant={resolveLandingVariant({})}
          assignmentSource="experiment"
        />,
      );
      const input = screen.getByRole('textbox', { name: 'Email' });
      fireEvent.focus(input);
      fireEvent.blur(input);
      fireEvent.focus(input);
      fireEvent.change(input, { target: { value: 'synthetic@example.com' } });
      fireEvent.click(screen.getByRole('button', { name: 'Get early access' }));
      await waitFor(() =>
        expect(analytics.track).toHaveBeenCalledWith(
          'web_waitlist_submit_result',
          expect.objectContaining({
            outcome,
            variant: 'waitlist_editorial_v2',
            assignment_source: 'experiment',
          }),
        ),
      );
      expect(
        jest.mocked(analytics.track).mock.calls.filter(([name]) => name === 'web_waitlist_started'),
      ).toHaveLength(1);
      expect(analytics.track).toHaveBeenCalledWith(
        'web_waitlist_submit_attempted',
        expect.objectContaining({ variant: 'waitlist_editorial_v2' }),
      );
      expect(JSON.stringify(jest.mocked(analytics.track).mock.calls)).not.toMatch(
        /synthetic@example|existing/,
      );
      if (outcome === 'accepted') {
        expect(screen.getByRole('status')).toHaveTextContent(
          "You're on the early-access list. We'll email you when your invite is ready.",
        );
        expect(screen.getByRole('button', { name: 'Get early access' })).toBeDisabled();
      }
    },
  );

  it('records a bounded network failure and permits retry', async () => {
    global.fetch = jest.fn().mockRejectedValue(new Error('private failure details'));
    render(
      <ExperimentWaitlistLanding
        variant={resolveLandingVariant({})}
        assignmentSource="experiment"
      />,
    );
    fireEvent.change(screen.getByRole('textbox', { name: 'Email' }), {
      target: { value: 'synthetic@example.com' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Get early access' }));
    await waitFor(() =>
      expect(analytics.track).toHaveBeenCalledWith(
        'web_waitlist_submit_result',
        expect.objectContaining({ outcome: 'server_error' }),
      ),
    );
    expect(screen.getByRole('button', { name: 'Get early access' })).toBeEnabled();
    expect(JSON.stringify(jest.mocked(analytics.track).mock.calls)).not.toMatch(
      /private failure|synthetic@example/,
    );
  });
});
