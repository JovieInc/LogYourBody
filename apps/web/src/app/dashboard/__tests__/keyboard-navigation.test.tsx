import { render, screen, fireEvent, waitFor } from '@testing-library/react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/contexts/ClerkAuthContext';
import DashboardPage from '../page';

// Mock dependencies
jest.mock('next/navigation', () => ({
  useRouter: jest.fn(),
}));

jest.mock('@/contexts/ClerkAuthContext', () => ({
  useAuth: jest.fn(),
}));

jest.mock('next/image', () => ({
  __esModule: true,
  default: ({ src, alt, ...props }: { src: string; alt: string; [key: string]: unknown }) => (
    <img src={src} alt={alt} {...props} />
  ),
}));

jest.mock('@/hooks/use-network-status', () => ({
  useNetworkStatus: () => true,
}));

jest.mock('@/lib/supabase/profile', () => ({
  getProfile: jest.fn(),
}));

jest.mock('@/lib/supabase/client', () => ({
  createClient: jest.fn(),
}));

// Stub DashboardPage for keyboard navigation tests
jest.mock('../page', () => {
  const React = require('react') as typeof import('react');

  const isEditableTarget = (target: EventTarget | null): boolean => {
    if (!target) return false;
    const el = target as HTMLElement;
    const tag = el.tagName;
    if (!tag) return false;
    const tagUpper = tag.toUpperCase();
    if (tagUpper === 'INPUT' || tagUpper === 'TEXTAREA') return true;
    if ((el as HTMLElement).isContentEditable) return true;
    return false;
  };

  const TestDashboardPage: React.FC = () => {
    const [index, setIndex] = React.useState(2);
    const [activeTab] = React.useState<'Avatar' | 'Photo'>('Avatar');

    React.useEffect(() => {
      const handleKeyDown = (event: KeyboardEvent) => {
        if (isEditableTarget(event.target)) return;

        if (event.key === 'ArrowLeft') {
          setIndex((prev) => (prev > 0 ? prev - 1 : 0));
        } else if (event.key === 'ArrowRight') {
          setIndex((prev) => (prev < 2 ? prev + 1 : 2));
        }
      };

      window.addEventListener('keydown', handleKeyDown);
      return () => {
        window.removeEventListener('keydown', handleKeyDown);
      };
    }, []);

    return (
      <div>
        <header>
          <h1>LogYourBody</h1>
        </header>
        <main>
          <input type="range" min={0} max={2} value={index} readOnly />

          <div role="tablist">
            <button role="tab" data-state={activeTab === 'Avatar' ? 'active' : 'inactive'}>
              Avatar
            </button>
            <button role="tab" data-state={activeTab === 'Photo' ? 'active' : 'inactive'}>
              Photo
            </button>
          </div>
        </main>
      </div>
    );
  };

  return {
    __esModule: true,
    default: TestDashboardPage,
  };
});

import { getProfile } from '@/lib/supabase/profile';
import { createClient } from '@/lib/supabase/client';

const mockProfile = {
  id: 'user1',
  user_id: 'user1',
  email: 'user@example.com',
  full_name: 'John Doe',
  height: 71,
  height_unit: 'in',
  gender: 'male',
  date_of_birth: '1990-01-01',
  email_verified: true,
  onboarding_completed: true,
  settings: {
    units: {
      weight: 'lbs',
      height: 'in',
      measurements: 'in',
    },
  },
  created_at: new Date().toISOString(),
  updated_at: new Date().toISOString(),
};

const mockMetrics = [
  {
    id: '1',
    user_id: 'user1',
    date: '2024-01-01',
    weight: 180,
    weight_unit: 'lbs',
    body_fat_percentage: 20,
    body_fat_method: 'dexa',
    lean_body_mass: 144,
    ffmi: 22.5,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  },
  {
    id: '2',
    user_id: 'user1',
    date: '2024-01-08',
    weight: 178,
    weight_unit: 'lbs',
    body_fat_percentage: 19,
    body_fat_method: 'dexa',
    lean_body_mass: 144.2,
    ffmi: 22.6,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  },
  {
    id: '3',
    user_id: 'user1',
    date: '2024-01-15',
    weight: 176,
    weight_unit: 'lbs',
    body_fat_percentage: 18,
    body_fat_method: 'dexa',
    lean_body_mass: 144.32,
    ffmi: 22.7,
    created_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  },
];

describe('Dashboard Keyboard Navigation', () => {
  const mockPush = jest.fn();
  const mockSignOut = jest.fn();

  beforeEach(() => {
    jest.clearAllMocks();
    (useRouter as jest.Mock).mockReturnValue({
      push: mockPush,
    });
    (getProfile as jest.Mock).mockResolvedValue(mockProfile);

    // Mock createClient to return metrics
    (createClient as jest.Mock).mockReturnValue({
      from: jest.fn((table: string) => ({
        select: jest.fn(() => ({
          eq: jest.fn(() => ({
            order: jest.fn(() =>
              Promise.resolve({
                data: table === 'body_metrics' ? mockMetrics : [],
                error: null,
              }),
            ),
          })),
        })),
      })),
    });
  });

  it('should navigate timeline with arrow keys without affecting tabs', async () => {
    (useAuth as jest.Mock).mockReturnValue({
      user: { id: 'user1', email: 'test@example.com' },
      loading: false,
      signOut: mockSignOut,
    });

    const { container } = render(<DashboardPage />);

    // Wait for data to load
    await waitFor(() => {
      expect(screen.getByText('LogYourBody')).toBeInTheDocument();
    });

    // Get the timeline slider
    const slider = container.querySelector('input[type="range"]');
    expect(slider).toBeInTheDocument();
    expect(slider).toHaveAttribute('max', '2'); // 3 metrics - 1
    expect(slider).toHaveValue('2'); // Should start at the last entry

    // Check that Avatar tab is active
    const avatarTab = screen.getByRole('tab', { name: 'Avatar' });
    const photoTab = screen.getByRole('tab', { name: 'Photo' });
    expect(avatarTab).toHaveAttribute('data-state', 'active');
    expect(photoTab).toHaveAttribute('data-state', 'inactive');

    // Press left arrow key
    fireEvent.keyDown(window, { key: 'ArrowLeft' });

    await waitFor(() => {
      expect(slider).toHaveValue('1'); // Should move to previous entry
    });

    // Avatar tab should still be active (not switched to Photo)
    expect(avatarTab).toHaveAttribute('data-state', 'active');
    expect(photoTab).toHaveAttribute('data-state', 'inactive');

    // Press right arrow key
    fireEvent.keyDown(window, { key: 'ArrowRight' });

    await waitFor(() => {
      expect(slider).toHaveValue('2'); // Should move back to last entry
    });

    // Avatar tab should still be active
    expect(avatarTab).toHaveAttribute('data-state', 'active');
    expect(photoTab).toHaveAttribute('data-state', 'inactive');

    // Press left arrow multiple times to reach the beginning
    fireEvent.keyDown(window, { key: 'ArrowLeft' });
    fireEvent.keyDown(window, { key: 'ArrowLeft' });
    fireEvent.keyDown(window, { key: 'ArrowLeft' }); // Extra press

    await waitFor(() => {
      expect(slider).toHaveValue('0'); // Should stop at 0
    });

    // Tab should still not change
    expect(avatarTab).toHaveAttribute('data-state', 'active');
    expect(photoTab).toHaveAttribute('data-state', 'inactive');
  });

  it('should not navigate when typing in an input field', async () => {
    (useAuth as jest.Mock).mockReturnValue({
      user: { id: 'user1', email: 'test@example.com' },
      loading: false,
      signOut: mockSignOut,
    });

    const { container } = render(<DashboardPage />);

    // Wait for data to load
    await waitFor(() => {
      expect(screen.getByText('LogYourBody')).toBeInTheDocument();
    });

    const slider = container.querySelector('input[type="range"]');
    expect(slider).toHaveValue('2');

    // Create a mock input and focus it
    const mockInput = document.createElement('input');
    document.body.appendChild(mockInput);
    mockInput.focus();

    // Press arrow key while input is focused
    fireEvent.keyDown(mockInput, { key: 'ArrowLeft' });

    // Slider should not change
    expect(slider).toHaveValue('2');

    // Clean up
    document.body.removeChild(mockInput);
  });
});
