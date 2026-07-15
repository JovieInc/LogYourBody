import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import type { HTMLAttributes, JSX } from 'react';
import { ExperimentWaitlistLanding } from '../ExperimentWaitlistLanding';
import { resolveLandingVariant } from '@/lib/marketing/landing-registry';

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

  it('renders one conversion path with no navigation or unverified social proof', () => {
    render(
      <ExperimentWaitlistLanding
        variant={resolveLandingVariant({ audience: 'women', goal: 'recomposition' })}
        assignmentSource="campaign"
      />,
    );

    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(
      'Know if the work is working.',
    );
    expect(screen.getByRole('textbox', { name: 'Email' })).toBeInTheDocument();
    expect(screen.getAllByRole('button', { name: 'Get early access' })).toHaveLength(1);
    expect(screen.queryByRole('navigation')).not.toBeInTheDocument();
    expect(screen.queryByRole('link')).not.toBeInTheDocument();
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
    expect(await screen.findByText(/you're on the list/i)).toBeInTheDocument();
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
  });
});
