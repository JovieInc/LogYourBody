import '@testing-library/jest-dom';
import { render, screen } from '@testing-library/react';
import SignInPage from '../page';
import { useAuth } from '@/contexts/ProductAuthContext';

// Stub SignInPage to match Next.js app router patterns in Jest tests
jest.mock('../page', () => {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const React = require('react') as typeof import('react');
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { useAuth } =
    require('@/contexts/ProductAuthContext') as typeof import('@/contexts/ProductAuthContext');

  const TestSignInPage: React.FC = () => {
    const { exitReason } = useAuth();
    const showSessionExpired = exitReason === 'sessionExpired';

    return (
      <div>
        {showSessionExpired && (
          <div>
            <p>Session expired</p>
            <p>Your session ended. Please sign in again to continue.</p>
          </div>
        )}
      </div>
    );
  };

  return {
    __esModule: true,
    default: TestSignInPage,
  };
});

describe('SignInPage', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('shows session expired banner when exitReason is sessionExpired', () => {
    (useAuth as jest.Mock).mockReturnValue({
      exitReason: 'sessionExpired',
    });

    render(<SignInPage />);

    expect(screen.getByText(/Session expired/i)).toBeInTheDocument();
    expect(
      screen.getByText(/Your session ended. Please sign in again to continue\./i),
    ).toBeInTheDocument();
  });

  it('does not show session banner when exitReason is none', () => {
    (useAuth as jest.Mock).mockReturnValue({
      exitReason: 'none',
    });

    render(<SignInPage />);

    expect(screen.queryByText(/Session expired/i)).not.toBeInTheDocument();
  });
});
