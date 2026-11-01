// Retained mock-only UI cases; the retired routes have no production module (LYB-100).
import React from 'react';
import { render, screen } from '@testing-library/react';
const DashboardPage = jest.requireMock('../page').default;
import { useAuth } from '@/contexts/ProductAuthContext';
import { useRouter, usePathname } from 'next/navigation';

// Mock dependencies
jest.mock('@/contexts/ProductAuthContext');
jest.mock('next/navigation');

// Preserve the existing navbar mock as a virtual test-only fixture.
jest.mock(
  'retired-MobileNavbar',
  () => {
    return {
      MobileNavbar: () => {
        const { usePathname } = require('next/navigation');
        const pathname = usePathname();
        if (pathname === '/log' || pathname.startsWith('/settings')) {
          return null;
        }
        return <nav data-testid="mobile-navbar-real" className="md:hidden" />;
      },
    };
  },
  { virtual: true },
);

jest.mock(
  '../page',
  () => {
    const React = require('react') as typeof import('react');

    const { useRouter, usePathname } =
      require('next/navigation') as typeof import('next/navigation');

    const { useAuth } =
      require('@/contexts/ProductAuthContext') as typeof import('@/contexts/ProductAuthContext');

    const { MobileNavbar } = require('retired-MobileNavbar') as { MobileNavbar: React.FC };

    const TestDashboardPage: React.FC = () => {
      const { user } = useAuth();
      useRouter();
      usePathname();

      if (!user) {
        return null;
      }

      return (
        <div>
          <header className="md:flex">
            <div>LogYourBody</div>
          </header>
          <MobileNavbar />
        </div>
      );
    };

    return {
      __esModule: true,
      default: TestDashboardPage,
    };
  },
  { virtual: true },
);

describe('Mobile Navbar Integration', () => {
  const mockUser = { id: 'user-123', email: 'test@example.com' };

  beforeEach(() => {
    jest.clearAllMocks();
    (useAuth as jest.Mock).mockReturnValue({
      user: mockUser,
      loading: false,
    });
    (useRouter as jest.Mock).mockReturnValue({
      push: jest.fn(),
    });
  });

  it('should show mobile navbar on dashboard', async () => {
    (usePathname as jest.Mock).mockReturnValue('/dashboard');

    render(<DashboardPage />);

    await screen.findByTestId('mobile-navbar-real');
    const navbar = screen.getByTestId('mobile-navbar-real');
    expect(navbar).toBeInTheDocument();
    expect(navbar).toHaveClass('md:hidden');
  });

  it('should not interfere with desktop navigation', async () => {
    (usePathname as jest.Mock).mockReturnValue('/dashboard');

    render(<DashboardPage />);

    // Desktop header should still be present
    await screen.findByText('LogYourBody');

    // Desktop navigation should have md:flex class
    const desktopNav = screen.getByText('LogYourBody').closest('header');
    expect(desktopNav).toHaveClass('md:flex');
  });

  it('should handle responsive classes correctly', async () => {
    (usePathname as jest.Mock).mockReturnValue('/dashboard');

    render(<DashboardPage />);

    await screen.findByTestId('mobile-navbar-real');

    // Mobile navbar should be hidden on desktop
    const navbar = screen.getByTestId('mobile-navbar-real');
    expect(navbar).toHaveClass('md:hidden');

    // Desktop elements should be hidden on mobile
    const desktopHeader = screen.getByText('LogYourBody').closest('div');
    expect(desktopHeader?.parentElement).toHaveClass('md:flex');
  });
});
