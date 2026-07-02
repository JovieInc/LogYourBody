import { render, screen } from '@testing-library/react';
import { MinimalWaitlistLanding } from '../MinimalWaitlistLanding';
import { waitlistLandingCopy } from '../waitlist-copy';

jest.mock('@/lib/analytics', () => ({
  analytics: {
    track: jest.fn(),
  },
}));

describe('MinimalWaitlistLanding', () => {
  it('renders a single 100vh waitlist hero without unverified marketing claims', () => {
    render(<MinimalWaitlistLanding />);

    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(
      waitlistLandingCopy.headline,
    );
    expect(screen.getByText(waitlistLandingCopy.subheading)).toBeInTheDocument();
    expect(
      screen.getByRole('button', { name: waitlistLandingCopy.submitLabel }),
    ).toBeInTheDocument();

    expect(screen.queryByText(/10,000\+/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/93%/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/App Store rating/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/Download for iOS/i)).not.toBeInTheDocument();
  });
});
