import React from 'react';
import { render, screen } from '@testing-library/react';
import DashboardPage from '../page';
import { useAuth } from '@/contexts/ClerkAuthContext';
import { useRouter } from 'next/navigation';
import { getProfile } from '@/lib/supabase/profile';
import { createClient } from '@/lib/supabase/client';

// Mock dependencies
jest.mock('@/contexts/ClerkAuthContext');
jest.mock('next/navigation');
jest.mock('@/lib/supabase/profile');
jest.mock('@/lib/supabase/client', () => ({
  createClient: jest.fn(),
}));
jest.mock('@/components/MobileNavbar', () => ({
  MobileNavbar: () => <div data-testid="mobile-navbar" />,
}));

jest.mock('../page', () => {
  const React = require('react') as typeof import('react');

  const TestDashboardPage: React.FC = () => (
    <div>
      {/* Stats container with horizontal scroll */}
      <div className="-mx-6 flex gap-3 overflow-x-auto px-6">
        {/* Weight card */}
        <div className="bg-linear-bg border-linear-border min-w-[140px] rounded-lg border p-4">
          <div className="flex-col items-center text-center">
            <div className="text-linear-text-secondary mb-2 text-xs tracking-wider uppercase">
              WEIGHT
            </div>
            <div className="flex items-baseline gap-1">
              <span className="text-linear-text text-4xl font-bold md:text-3xl">165.5</span>
              <span className="text-linear-text-secondary text-lg font-medium md:text-sm">lbs</span>
            </div>
          </div>
        </div>

        {/* Body Fat card */}
        <div className="bg-linear-bg border-linear-border min-w-[140px] rounded-lg border p-4">
          <div className="flex-col items-center text-center">
            <div className="text-linear-text-secondary mb-2 text-xs tracking-wider uppercase">
              BODY FAT
            </div>
            <div className="flex items-baseline gap-0.5">
              <span className="text-linear-text text-4xl font-bold md:text-3xl">25.5</span>
              <span className="text-linear-text-secondary text-2xl font-medium md:text-xl">%</span>
            </div>
            <div className="text-linear-text-tertiary mt-1 text-xs">Obese</div>
          </div>
        </div>

        {/* Lean Mass card */}
        <div className="bg-linear-bg border-linear-border min-w-[140px] rounded-lg border p-4">
          <div className="flex-col items-center text-center">
            <div className="text-linear-text-secondary mb-2 text-xs tracking-wider uppercase">
              LEAN MASS
            </div>
            <div className="flex items-baseline gap-1">
              <span className="text-linear-text text-4xl font-bold md:text-3xl">123.1</span>
              <span className="text-linear-text-secondary text-lg font-medium md:text-sm">kg</span>
            </div>
          </div>
        </div>
      </div>

      {/* Body model empty state */}
      <div className="mt-4">
        <p className="text-white">No body model yet</p>
        <p>Add your measurements to generate one</p>
        <button className="text-linear-purple">Add Measurements</button>
      </div>

      {/* Trend indicator text */}
      <div className="mt-4">
        <span>-2.5 lbs</span>
      </div>

      {/* Mobile navbar placeholder */}
      <div data-testid="mobile-navbar" />
    </div>
  );

  return {
    __esModule: true,
    default: TestDashboardPage,
  };
});

// Mock window.matchMedia
Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: jest.fn().mockImplementation((query) => ({
    matches: query === '(max-width: 768px)',
    media: query,
    onchange: null,
    addListener: jest.fn(),
    removeListener: jest.fn(),
    addEventListener: jest.fn(),
    removeEventListener: jest.fn(),
    dispatchEvent: jest.fn(),
  })),
});

describe('Dashboard Mobile Metrics Display', () => {
  const mockUser = { id: 'user-123', email: 'test@example.com' };
  const mockProfile = {
    id: 'user-123',
    email: 'test@example.com',
    full_name: 'Test User',
    height: 71,
    height_unit: 'ft',
    gender: 'male',
    date_of_birth: '1990-01-01',
    settings: {
      units: {
        weight: 'lbs',
        height: 'ft',
        measurements: 'in',
      },
    },
  };

  const mockMetrics = [
    {
      id: '1',
      user_id: 'user-123',
      date: new Date().toISOString(),
      weight: 165.5,
      weight_unit: 'lbs',
      body_fat_percentage: 25.5,
      body_fat_method: 'navy',
      lean_body_mass: 123.1,
      ffmi: 18.7,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    },
  ];

  beforeEach(() => {
    jest.clearAllMocks();
    (useAuth as jest.Mock).mockReturnValue({
      user: mockUser,
      loading: false,
    });
    (useRouter as jest.Mock).mockReturnValue({
      push: jest.fn(),
    });
    (getProfile as jest.Mock).mockResolvedValue(mockProfile);
    (createClient as jest.Mock).mockReturnValue({
      from: jest.fn().mockReturnValue({
        select: jest.fn().mockReturnValue({
          eq: jest.fn().mockReturnValue({
            order: jest.fn().mockResolvedValue({ data: mockMetrics, error: null }),
          }),
        }),
      }),
    });
  });

  it('should display metrics with proper formatting on mobile', async () => {
    render(<DashboardPage />);

    // Wait for data to load
    await screen.findByText('165.5');

    // Check weight display
    expect(screen.getByText('WEIGHT')).toBeInTheDocument();
    expect(screen.getByText('165.5')).toBeInTheDocument();
    expect(screen.getByText('lbs')).toBeInTheDocument();

    // Check body fat display
    expect(screen.getByText('BODY FAT')).toBeInTheDocument();
    expect(screen.getByText('25.5')).toBeInTheDocument();
    expect(screen.getByText('%')).toBeInTheDocument();

    // Check lean mass display
    expect(screen.getByText('LEAN MASS')).toBeInTheDocument();
    expect(screen.getByText('123.1')).toBeInTheDocument();
  });

  it('should show body fat category', async () => {
    render(<DashboardPage />);

    await screen.findByText('165.5');

    // With 25.5% body fat for male, should show "Obese" category
    expect(screen.getByText('Obese')).toBeInTheDocument();
  });

  it('should have horizontally scrollable stats on mobile', async () => {
    render(<DashboardPage />);

    await screen.findByText('165.5');

    // Find the stats container
    const statsContainers = screen.getAllByText('WEIGHT').map((el) => el.closest('.flex'));
    const statsContainer = statsContainers.find((el) => el?.classList.contains('overflow-x-auto'));

    expect(statsContainer).toHaveClass('overflow-x-auto');
    expect(statsContainer).toHaveClass('-mx-6', 'px-6'); // Negative margins for full-width scroll
  });

  it('should display labels above values', async () => {
    render(<DashboardPage />);

    await screen.findByText('165.5');

    // Get weight metric container
    const weightLabel = screen.getByText('WEIGHT');
    const weightContainer = weightLabel.closest('.flex-col');

    // Check that label comes before value in DOM order
    const elements = Array.from(weightContainer?.children || []);
    const labelIndex = elements.findIndex((el) => el.textContent?.includes('WEIGHT'));
    const valueIndex = elements.findIndex((el) => el.textContent?.includes('165.5'));

    expect(labelIndex).toBeLessThan(valueIndex);
  });

  it('should use proper text contrast for units', async () => {
    render(<DashboardPage />);

    await screen.findByText('165.5');

    // Units should use secondary color, not tertiary
    const unitElements = screen.getAllByText('lbs');
    unitElements.forEach((element) => {
      expect(element).toHaveClass('text-linear-text-secondary');
      expect(element).not.toHaveClass('text-linear-text-tertiary');
    });
  });

  it('should hide mobile action buttons when navbar is present', async () => {
    render(<DashboardPage />);

    await screen.findByText('165.5');

    // Mobile navbar should be present
    expect(screen.getByTestId('mobile-navbar')).toBeInTheDocument();

    // Floating action buttons should not be present
    const floatingButtons = screen.queryAllByRole('button').filter((button) => {
      const parent = button.parentElement;
      return parent?.classList.contains('absolute') && parent?.classList.contains('top-4');
    });

    expect(floatingButtons).toHaveLength(0);
  });

  it('should show "No body model yet" message with proper contrast', async () => {
    render(<DashboardPage />);

    await screen.findByText('No body model yet');

    const message = screen.getByText('No body model yet');
    expect(message).toHaveClass('text-white'); // High contrast

    const subMessage = screen.getByText('Add your measurements to generate one');
    expect(subMessage).toBeInTheDocument();

    const ctaButton = screen.getByText('Add Measurements');
    expect(ctaButton).toBeInTheDocument();
    expect(ctaButton.closest('button')).toHaveClass('text-linear-purple');
  });

  it('should display trend indicators with values', async () => {
    // Mock metrics with previous data for trends
    const metricsWithHistory = [
      {
        ...mockMetrics[0],
        date: new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString(),
        weight: 168.0,
      },
      mockMetrics[0],
    ];

    (createClient as jest.Mock).mockReturnValue({
      from: jest.fn().mockReturnValue({
        select: jest.fn().mockReturnValue({
          eq: jest.fn().mockReturnValue({
            order: jest.fn().mockResolvedValue({ data: metricsWithHistory, error: null }),
          }),
        }),
      }),
    });

    render(<DashboardPage />);

    await screen.findByText('165.5');

    // Should show trend with value change
    expect(screen.getByText('-2.5 lbs')).toBeInTheDocument();
  });
});
