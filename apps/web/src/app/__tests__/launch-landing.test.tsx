import { render, screen } from '@testing-library/react';
import { logYourBody } from '@jovieinc/product-registry';
import { launchLandingCopy, launchLandingFeatures } from '../launch-landing-copy';
import { waitlistLandingCopy } from '../waitlist-copy';

jest.mock('@/lib/analytics', () => ({
  analytics: { track: jest.fn() },
}));

jest.mock('@/lib/flags/landing', () => ({
  LANDING_FLAGS: {
    WAITLIST_V2_ENABLED: false,
    ART_DIRECTION_V2_ENABLED: false,
    APP_STORE_LIVE: false,
  },
}));

import { LANDING_FLAGS } from '@/lib/flags/landing';
import { LaunchLanding } from '../LaunchLanding';

const flags = LANDING_FLAGS as { APP_STORE_LIVE: boolean };

async function renderLanding(appStoreLive: boolean) {
  flags.APP_STORE_LIVE = appStoreLive;
  return render(<LaunchLanding />);
}

describe('LaunchLanding', () => {
  it('leads with the registry promise, the product render, features and the plan', async () => {
    await renderLanding(false);

    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(
      logYourBody.messages.landing.headline,
    );
    expect(screen.getByText(launchLandingCopy.subheading)).toBeInTheDocument();
    expect(screen.getByAltText(launchLandingCopy.heroImageAlt)).toHaveAttribute(
      'src',
      expect.stringContaining('home-metric-first'),
    );

    for (const feature of launchLandingFeatures) {
      expect(screen.getByRole('heading', { level: 3, name: feature.name })).toBeInTheDocument();
      expect(screen.getByText(feature.description)).toBeInTheDocument();
    }
    expect(launchLandingFeatures.length).toBeGreaterThanOrEqual(3);

    expect(screen.getByText(launchLandingCopy.pricingLine)).toHaveTextContent('3-day free trial');
    expect(screen.getByText(launchLandingCopy.pricingLine)).toHaveTextContent('$9.99');
    expect(screen.getByText(launchLandingCopy.pricingLine)).toHaveTextContent('$69.99');
  });

  it('asks for the waitlist while the App Store listing is not live', async () => {
    await renderLanding(false);

    expect(screen.getAllByRole('textbox')).toHaveLength(1);
    expect(screen.getByRole('link', { name: waitlistLandingCopy.submitLabel })).toHaveAttribute(
      'href',
      '#early-access',
    );
    expect(screen.queryByRole('link', { name: launchLandingCopy.appStoreCta })).toBeNull();
  });

  it('switches every primary action to the App Store once the listing is live', async () => {
    await renderLanding(true);

    const links = screen.getAllByRole('link', { name: launchLandingCopy.appStoreCta });
    expect(links).toHaveLength(2);
    for (const link of links) {
      expect(link).toHaveAttribute('href', logYourBody.links.appStore);
    }
    expect(screen.queryByRole('textbox')).toBeNull();
  });
});
