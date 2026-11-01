import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import { MobileNavbar } from '../MobileNavbar';
import { useRouter, usePathname } from 'next/navigation';

jest.mock('next/navigation', () => ({
  useRouter: jest.fn(),
  usePathname: jest.fn(),
}));

jest.mock('lucide-react', () => {
  const React = require('react');
  function Icon(props: { className?: string }) {
    return React.createElement('svg', props);
  }
  return { __esModule: true, default: Icon, Home: Icon, Settings: Icon };
});

describe('MobileNavbar', () => {
  const mockPush = jest.fn();

  beforeEach(() => {
    jest.clearAllMocks();
    (useRouter as jest.Mock).mockReturnValue({
      push: mockPush,
    });
  });

  it('should render the launch home and settings actions', () => {
    (usePathname as jest.Mock).mockReturnValue('/');

    render(<MobileNavbar />);

    expect(screen.getByLabelText('Home')).toBeInTheDocument();
    expect(screen.getByLabelText('Settings')).toBeInTheDocument();
    expect(screen.queryByLabelText('Add Data')).not.toBeInTheDocument();
    expect(screen.queryByLabelText('Dashboard')).not.toBeInTheDocument();
  });

  it('should not render on log page', () => {
    (usePathname as jest.Mock).mockReturnValue('/log');

    const { container } = render(<MobileNavbar />);

    expect(container.firstChild).toBeNull();
  });

  it('should not render on settings pages', () => {
    (usePathname as jest.Mock).mockReturnValue('/settings/profile');

    const { container } = render(<MobileNavbar />);

    expect(container.firstChild).toBeNull();
  });

  it('should highlight active route', () => {
    (usePathname as jest.Mock).mockReturnValue('/');

    render(<MobileNavbar />);

    const homeButton = screen.getByLabelText('Home');
    const settingsButton = screen.getByLabelText('Settings');

    const homeIcon = homeButton.querySelector('svg');
    expect(homeIcon).toHaveClass('text-linear-purple');

    const settingsIcon = settingsButton.querySelector('svg');
    expect(settingsIcon).toHaveClass('text-linear-text-secondary');
  });

  it('should navigate when buttons are clicked', () => {
    (usePathname as jest.Mock).mockReturnValue('/');

    render(<MobileNavbar />);

    fireEvent.click(screen.getByLabelText('Settings'));
    expect(mockPush).toHaveBeenCalledWith('/settings');

    fireEvent.click(screen.getByLabelText('Home'));
    expect(mockPush).toHaveBeenCalledWith('/');
  });

  it('should be hidden on desktop', () => {
    (usePathname as jest.Mock).mockReturnValue('/');

    const { container } = render(<MobileNavbar />);

    const navbar = container.querySelector('.fixed.bottom-0');
    expect(navbar).toHaveClass('md:hidden');
  });

  it('should have correct height and positioning', () => {
    (usePathname as jest.Mock).mockReturnValue('/');

    const { container } = render(<MobileNavbar />);

    const navbar = container.querySelector('.fixed.bottom-0');
    expect(navbar).toHaveClass('fixed', 'bottom-0', 'left-0', 'right-0');

    // Height is on the inner container
    const innerContainer = navbar?.querySelector('.h-14');
    expect(innerContainer).toBeInTheDocument();
    expect(innerContainer).toHaveClass('h-14');
  });
});
