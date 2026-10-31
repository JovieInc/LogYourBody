import { readFileSync } from 'node:fs';
import path from 'node:path';
import type { HTMLAttributes, JSX } from 'react';
import { render, screen, within } from '@testing-library/react';
import { MARKETING_LEGAL_LINKS } from '@/data/marketingNavigation';
import { MarketingPage } from '@/components/MarketingPage';
import { resolveLandingVariant } from '@/lib/marketing/landing-registry';
import { LaunchLanding } from '../LaunchLanding';
import { MinimalWaitlistLanding } from '../MinimalWaitlistLanding';
import { ExperimentWaitlistLanding } from '../ExperimentWaitlistLanding';

jest.mock('@/lib/analytics', () => ({ analytics: { track: jest.fn() } }));
jest.mock('@/components/Header', () => ({ Header: () => <header /> }));
jest.mock('@/lib/flags/landing', () => ({
  LANDING_FLAGS: { ART_DIRECTION_V2_ENABLED: false, APP_STORE_LIVE: false },
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

describe('consumer health data policy publication guard', () => {
  it('retains the distinct policy in the homepage footer link list', () => {
    expect(MARKETING_LEGAL_LINKS).toContainEqual({
      href: '/consumer-health-data',
      label: 'Consumer health data',
    });
  });

  it('retains the canonical policy file and its required sections', () => {
    const policy = readFileSync(
      path.resolve(process.cwd(), '../../shared/legal/consumer-health-data-policy.md'),
      'utf8',
    );
    for (const section of [
      'Consumer health data we collect',
      'Who we share it with',
      'Your rights',
    ]) {
      expect(policy.split(/\r?\n/)).toContain(`## ${section}`);
    }
  });

  it.each([
    ['LaunchLanding', <LaunchLanding key="launch" />],
    ['MinimalWaitlistLanding', <MinimalWaitlistLanding key="minimal" />],
    ['EditorialLanding', <LaunchLanding key="editorial" editorialEnabled />],
    [
      'ExperimentWaitlistLanding',
      <ExperimentWaitlistLanding
        key="experiment"
        variant={resolveLandingVariant({})}
        assignmentSource="experiment"
      />,
    ],
    ['MarketingPage', <MarketingPage key="marketing">Page content</MarketingPage>],
  ] as const)('shows the distinct policy link in the %s footer', (_name, page) => {
    render(page);
    const link = within(screen.getByRole('contentinfo')).getByRole('link', {
      name: 'Consumer health data',
    });
    expect(link).toBeVisible();
    expect(link).toHaveAttribute('href', '/consumer-health-data');
  });
});
