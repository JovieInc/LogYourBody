import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { logYourBody } from '@jovieinc/product-registry';
import { EditorialLanding } from '../EditorialLanding';
import { LANDING_PRODUCT_PROOF } from '@/lib/marketing/landing-registry';
import { launchLandingCopy } from '../launch-landing-copy';

jest.mock('@/lib/analytics', () => ({ analytics: { track: jest.fn() } }));
jest.mock('@/lib/flags/landing', () => ({
  LANDING_FLAGS: { ART_DIRECTION_V2_ENABLED: true, APP_STORE_LIVE: false },
}));

import { LaunchLanding } from '../LaunchLanding';

describe('EditorialLanding', () => {
  const originalFetch = global.fetch;
  afterEach(() => {
    global.fetch = originalFetch;
    jest.clearAllMocks();
  });

  it('renders an enabled server decision as a product-led homepage with one signup form', () => {
    const { container } = render(<LaunchLanding editorialEnabled />);
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(
      logYourBody.messages.landing.headline,
    );
    expect(screen.getByAltText(LANDING_PRODUCT_PROOF.alt)).toHaveAttribute(
      'src',
      expect.stringContaining('weight-log'),
    );
    expect(screen.getByText(launchLandingCopy.subheading)).toBeInTheDocument();
    expect(container.querySelectorAll('form')).toHaveLength(1);
    expect(screen.getAllByRole('textbox')).toHaveLength(1);
    expect(screen.getAllByRole('button', { name: 'Request early access' })).toHaveLength(1);
    const links = screen.getAllByRole('link', { name: 'Request early access' });
    expect(links).toHaveLength(3);
    for (const link of links) expect(link).toHaveAttribute('href', '#early-access');
    expect(container.querySelectorAll('#early-access')).toHaveLength(1);
    for (const link of screen
      .getByRole('navigation', { name: 'Homepage sections' })
      .querySelectorAll('a')) {
      expect(container.querySelector(link.hash)).toBeInTheDocument();
    }
  });

  it('distinguishes illustrative data from a real app capture and preserves source and price caveats', () => {
    render(
      <EditorialLanding
        appStoreLive={false}
        landingId="launch_waitlist_v1"
        variant="waitlist_editorial"
      />,
    );
    expect(
      screen.getByRole('figure', { name: /Illustrative weight timeline/ }),
    ).toBeInTheDocument();
    expect(screen.getByText('Illustrative timeline / 30 days')).toBeInTheDocument();
    expect(screen.getByText('Apple Health · measured')).toBeInTheDocument();
    expect(screen.getByText('Manual entry · estimated')).toBeInTheDocument();
    expect(
      screen.getByLabelText(
        `Reference price: ${launchLandingCopy.monthlyReferencePrice} USD per month`,
      ),
    ).toBeInTheDocument();
    expect(
      screen.getByText(`Or ${launchLandingCopy.annualReferencePrice} USD per year.`),
    ).toBeInTheDocument();
    expect(screen.getByText(launchLandingCopy.pricingNote)).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /Your body.*Your business/ })).toBeInTheDocument();
    expect(
      screen.queryByText(/app store rating|testimonials|users and counting/i),
    ).not.toBeInTheDocument();
  });

  it('keeps the existing durable waitlist flow and announces acceptance', async () => {
    global.fetch = jest
      .fn()
      .mockResolvedValue({ ok: true, status: 202, json: async () => ({ success: true }) });
    render(
      <EditorialLanding
        appStoreLive={false}
        landingId="launch_waitlist_v1"
        variant="waitlist_editorial"
      />,
    );
    fireEvent.change(screen.getByRole('textbox', { name: 'Email' }), {
      target: { value: 'reader@example.com' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Request early access' }));
    await waitFor(() => expect(global.fetch).toHaveBeenCalledTimes(1));
    expect(global.fetch).toHaveBeenCalledWith(
      '/api/waitlist',
      expect.objectContaining({ method: 'POST' }),
    );
    expect(await screen.findByText('Your early-access request was received.')).toBeInTheDocument();
  });

  it('sends every primary action to the App Store when the listing is live, without an email field', () => {
    render(
      <EditorialLanding appStoreLive landingId="launch_waitlist_v1" variant="waitlist_editorial" />,
    );
    expect(screen.queryByRole('textbox')).not.toBeInTheDocument();
    const links = screen.getAllByRole('link', { name: launchLandingCopy.appStoreCta });
    expect(links).toHaveLength(4);
    for (const link of links) expect(link).toHaveAttribute('href', logYourBody.links.appStore);
    expect(screen.queryByText(/Join the list for early access/)).not.toBeInTheDocument();
  });
});
