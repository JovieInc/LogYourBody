import { fireEvent, render, screen, within } from '@testing-library/react';
import type { HTMLAttributes, JSX } from 'react';
import { logYourBody } from '@jovieinc/product-registry';
import { LaunchLanding } from '../LaunchLanding';
import { MinimalWaitlistLanding } from '../MinimalWaitlistLanding';
import { LegacyMinimalWaitlistLanding } from '../LegacyMinimalWaitlistLanding';
import { ExperimentWaitlistLanding } from '../ExperimentWaitlistLanding';
import {
  LANDING_AUDIENCES,
  LANDING_GOALS,
  resolveLandingVariant,
} from '@/lib/marketing/landing-registry';
import { LANDING_FLAGS } from '@/lib/flags/landing';

jest.mock('@/lib/analytics', () => ({ analytics: { track: jest.fn() } }));
jest.mock('@/lib/flags/landing', () => ({
  LANDING_FLAGS: { APP_STORE_LIVE: false },
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

// Deliberately different prices and trial length catch hard-coded launch copy.
jest.mock('@jovieinc/product-registry', () => {
  const actual = jest.requireActual('@jovieinc/product-registry');
  const plan = actual.logYourBody.plans[0];
  return {
    ...actual,
    logYourBody: {
      ...actual.logYourBody,
      plans: [
        {
          ...plan,
          trialDays: 7,
          pricing: {
            ...plan.pricing,
            monthly: { ...plan.pricing.monthly, amount: 12.34 },
            annual: { ...plan.pricing.annual, amount: 87.65 },
          },
        },
      ],
    },
  };
});

const flags = LANDING_FLAGS as { APP_STORE_LIVE: boolean };

function expectFreeBetaPricing() {
  const pricing = screen.getByRole('region', { name: 'Pricing at launch' });
  expect(within(pricing).getByRole('heading', { name: 'Pricing at launch' })).toBeVisible();
  expect(pricing).toHaveTextContent(
    'Early access is a free TestFlight beta: you are not charged while you test.',
  );
  return pricing;
}

describe.each([
  ['standard', false],
  ['editorial', true],
] as const)('%s landing pricing', (_name, editorialEnabled) => {
  afterEach(() => {
    flags.APP_STORE_LIVE = false;
  });

  it('frames every prelaunch price as launch pricing and a free beta', () => {
    flags.APP_STORE_LIVE = false;
    render(<LaunchLanding editorialEnabled={editorialEnabled} />);
    const pricing = expectFreeBetaPricing();
    // No other section may show an unframed price.
    for (const element of screen.getAllByText(/\$\d/)) {
      expect(pricing).toContainElement(element);
    }
    expect(screen.queryByText(/Reference pric/)).not.toBeInTheDocument();
  });

  it('renders the price and trial values from the product registry', () => {
    flags.APP_STORE_LIVE = false;
    render(<LaunchLanding editorialEnabled={editorialEnabled} />);
    const plan = logYourBody.plans[0];
    expect(expectFreeBetaPricing()).toHaveTextContent(
      `$${plan.pricing.monthly.amount.toFixed(2)} a month or $${plan.pricing.annual.amount.toFixed(2)} a year (${plan.pricing.currency}), with a ${plan.trialDays}-day trial.`,
    );
  });

  it('preserves the existing live-store pricing copy', () => {
    flags.APP_STORE_LIVE = true;
    render(<LaunchLanding editorialEnabled={editorialEnabled} />);
    if (editorialEnabled) {
      expect(screen.getByLabelText('Reference price: $12.34 USD per month')).toBeVisible();
      expect(screen.getByText('Or $87.65 USD per year.')).toBeVisible();
      expect(screen.getByRole('heading', { name: /Make room.*for the long game/ })).toBeVisible();
    } else {
      expect(screen.getByRole('heading', { name: 'Pro' })).toBeVisible();
      expect(
        screen.getByText('Reference pricing: $12.34 a month or $87.65 a year (USD).'),
      ).toBeVisible();
    }
    expect(screen.queryByText(/not charged while you test/)).not.toBeInTheDocument();
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument();
  });
});

const waitlistVariants = [
  { name: 'standard', element: <LaunchLanding /> },
  { name: 'editorial', element: <LaunchLanding editorialEnabled /> },
  { name: 'minimal', element: <MinimalWaitlistLanding /> },
  { name: 'legacy', element: <LegacyMinimalWaitlistLanding /> },
  ...LANDING_AUDIENCES.flatMap((audience) =>
    LANDING_GOALS.map((goal) => ({
      name: `${audience}/${goal}`,
      element: (
        <ExperimentWaitlistLanding
          variant={resolveLandingVariant({ audience, goal })}
          assignmentSource="experiment"
        />
      ),
    })),
  ),
];

describe.each(waitlistVariants)('$name waitlist', ({ element }) => {
  const originalFetch = global.fetch;
  afterEach(() => {
    global.fetch = originalFetch;
  });

  it('frames any displayed price and explains what follows a successful request', async () => {
    flags.APP_STORE_LIVE = false;
    global.fetch = jest
      .fn()
      .mockResolvedValue({ ok: true, status: 202, json: async () => ({ success: true }) });
    render(element);
    for (const price of screen.queryAllByText(/\$\d/)) {
      expect(expectFreeBetaPricing()).toContainElement(price);
    }
    fireEvent.change(screen.getByRole('textbox', { name: 'Email' }), {
      target: { value: 'buyer@example.com' },
    });
    fireEvent.click(screen.getByRole('button', { name: /^(Request|Get) early access$/ }));
    expect(
      await screen.findByText(
        "You're on the early-access list. We'll email you when your invite is ready.",
      ),
    ).toBeVisible();
  });
});
