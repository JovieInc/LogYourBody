import { render, screen } from '@testing-library/react';
import { logYourBody } from '@jovieinc/product-registry';
import { LANDING_FLAGS } from '@/lib/flags/landing';
import { LANDING_PRODUCT_PROOF } from '@/lib/marketing/landing-registry';
import IOSDownloadPage, { metadata } from '../page';

jest.mock('@/lib/analytics', () => ({ analytics: { track: jest.fn() } }));
jest.mock('@/lib/flags/landing', () => ({
  LANDING_FLAGS: {
    APP_STORE_LIVE: false,
    WAITLIST_V2_ENABLED: false,
    ART_DIRECTION_V2_ENABLED: false,
  },
}));

const flags = LANDING_FLAGS as { APP_STORE_LIVE: boolean };

describe('iOS download acquisition surface', () => {
  it('describes the iOS product without inherited superiority or Android availability claims', () => {
    expect(metadata.title).toBe('LogYourBody for iPhone');
    expect(metadata.description).toBe(logYourBody.messages.landing.subheading);
    expect(JSON.stringify(metadata)).not.toMatch(/most advanced|Android/i);
  });
  it('uses the canonical promise and asks for early access while the listing gate is closed', () => {
    flags.APP_STORE_LIVE = false;
    const { container } = render(<IOSDownloadPage />);
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(
      logYourBody.messages.landing.headline,
    );
    expect(screen.getAllByRole('textbox')).toHaveLength(1);
    expect(screen.getByRole('button', { name: 'Request early access' })).toBeInTheDocument();
    expect(
      screen.queryByRole('link', { name: logYourBody.messages.landing.primaryCta }),
    ).toBeNull();
    expect(screen.queryByRole('table')).toBeNull();
    expect(container.textContent).not.toMatch(
      /Dr\. Sarah Chen|Mike Rodriguez|Emma Wilson|genetic (potential|limits)|thousands|generic fitness apps|download free|30.second logging/i,
    );
    expect(screen.getByAltText(LANDING_PRODUCT_PROOF.alt)).toHaveAttribute(
      'src',
      expect.stringContaining('weight-log'),
    );
  });

  it('uses the canonical App Store link only when the existing listing gate is enabled', () => {
    flags.APP_STORE_LIVE = true;
    render(<IOSDownloadPage />);
    const links = screen.getAllByRole('link', { name: logYourBody.messages.landing.primaryCta });
    expect(links).toHaveLength(2);
    for (const link of links) expect(link).toHaveAttribute('href', logYourBody.links.appStore);
    expect(screen.queryByRole('textbox')).toBeNull();
  });
});
