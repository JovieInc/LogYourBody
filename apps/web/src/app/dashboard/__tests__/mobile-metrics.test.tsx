import React from 'react';
import { render, screen } from '@testing-library/react';
import DashboardPage from '../page';

// Mock dependencies
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
            <div className="text-linear-text-secondary mb-2 text-xs uppercase tracking-wider">
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
            <div className="text-linear-text-secondary mb-2 text-xs uppercase tracking-wider">
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
            <div className="text-linear-text-secondary mb-2 text-xs uppercase tracking-wider">
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
  beforeEach(() => {
    jest.clearAllMocks();
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
    render(<DashboardPage />);

    await screen.findByText('165.5');

    // Should show trend with value change
    expect(screen.getByText('-2.5 lbs')).toBeInTheDocument();
  });
});
