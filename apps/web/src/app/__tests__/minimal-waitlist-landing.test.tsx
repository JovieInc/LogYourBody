import { render, screen } from '@testing-library/react';
import { MinimalWaitlistLanding } from '../MinimalWaitlistLanding';
import { waitlistLandingCopy } from '../waitlist-copy';

jest.mock('@/lib/analytics', () => ({
  analytics: {
    track: jest.fn(),
  },
}));

describe('MinimalWaitlistLanding', () => {
  it('renders the product promise, proof, waitlist, and canonical legal footer', () => {
    render(<MinimalWaitlistLanding />);

    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(
      waitlistLandingCopy.headline,
    );
    expect(screen.getByText(waitlistLandingCopy.subheading)).toBeInTheDocument();
    const primaryCta = screen.getByRole('button', { name: waitlistLandingCopy.submitLabel });
    expect(primaryCta).toHaveClass('min-h-11');
    expect(primaryCta.firstElementChild).toHaveClass('h-8');
    expect(screen.getAllByText(waitlistLandingCopy.submitLabel)).toHaveLength(1);
    expect(screen.getByRole('link', { name: /back to email/i })).toHaveAttribute(
      'href',
      '#early-access',
    );
    expect(
      screen.queryByText(/join to receive early-access and TestFlight invitations/i),
    ).not.toBeInTheDocument();
    expect(screen.getByTestId('landing-product-proof')).toBeInTheDocument();
    expect(
      screen.getByRole('heading', { level: 2, name: /one number is a moment/i }),
    ).toBeInTheDocument();
    expect(screen.getByRole('heading', { level: 2, name: /your progress/i })).toBeInTheDocument();
    expect(screen.getByText('Weight')).toBeInTheDocument();
    expect(screen.getByText('Body fat')).toBeInTheDocument();
    expect(screen.getByTestId('marketing-footer')).toHaveAttribute('data-footer-mode', 'full');
    expect(screen.getByRole('heading', { name: 'Product' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Privacy' })).toHaveAttribute('href', '/privacy');
    expect(screen.getByRole('link', { name: 'Terms' })).toHaveAttribute('href', '/terms');
    expect(screen.getByRole('link', { name: 'Health disclosure' })).toHaveAttribute(
      'href',
      '/health-disclosure',
    );

    expect(screen.queryByText(/10,000\+/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/93%/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/App Store rating/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/Download for iOS/i)).not.toBeInTheDocument();
  });
});
