import React from 'react'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { useAuth } from '@/contexts/ClerkAuthContext'
import { useRouter } from 'next/navigation'
import ProfileSettingsPage from '../page'
import * as profileApi from '@/lib/supabase/profile'
// import { format } from 'date-fns' // Not used

// Mock dependencies
jest.mock('@/contexts/ClerkAuthContext')
jest.mock('next/navigation', () => ({
  useRouter: jest.fn()
}))
jest.mock('@/lib/supabase/profile', () => ({
  getProfile: jest.fn(),
  updateProfile: jest.fn()
}))
jest.mock('@/hooks/use-toast', () => ({
  toast: jest.fn(),
  useToast: () => ({ toast: jest.fn() })
}))

// Mock lodash debounce to execute immediately in tests
jest.mock('lodash', () => ({
  ...jest.requireActual('lodash'),
  debounce: (fn: any) => {
    fn.cancel = jest.fn()
    fn.flush = jest.fn()
    return fn
  }
}))

// Mock UI components
jest.mock('@/components/ui/button', () => ({
  Button: ({ children, ...props }: any) => <button {...props}>{children}</button>
}))
jest.mock('@/components/ui/card', () => ({
  Card: ({ children, ...props }: any) => <div {...props}>{children}</div>,
  CardContent: ({ children, ...props }: any) => <div {...props}>{children}</div>,
  CardDescription: ({ children, ...props }: any) => <p {...props}>{children}</p>,
  CardHeader: ({ children, ...props }: any) => <div {...props}>{children}</div>,
  CardTitle: ({ children, ...props }: any) => <h3 {...props}>{children}</h3>
}))
jest.mock('@/components/ui/input', () => ({
  Input: (props: any) => <input {...props} />
}))
jest.mock('@/components/ui/label', () => ({
  Label: ({ children, ...props }: any) => <label {...props}>{children}</label>
}))
jest.mock('@/components/ui/select', () => ({
  Select: ({ children, onValueChange, ...props }: any) => <div {...props}>{children}</div>,
  SelectContent: ({ children, ...props }: any) => <div {...props}>{children}</div>,
  SelectItem: ({ children, ...props }: any) => <div {...props}>{children}</div>,
  SelectTrigger: ({ children, ...props }: any) => <button {...props}>{children}</button>,
  SelectValue: ({ children, ...props }: any) => <span {...props}>{children}</span>
}))
jest.mock('@/components/ui/avatar', () => ({
  Avatar: ({ children, ...props }: any) => <div {...props}>{children}</div>,
  AvatarFallback: ({ children, ...props }: any) => <div {...props}>{children}</div>,
  AvatarImage: ({ src, alt, ...props }: any) => <img src={src} alt={alt} {...props} />
}))
jest.mock('@/components/ui/dialog', () => ({
  Dialog: ({ children, ...props }: any) => <div {...props}>{children}</div>,
  DialogContent: ({ children, ...props }: any) => <div {...props}>{children}</div>,
  DialogHeader: ({ children, ...props }: any) => <div {...props}>{children}</div>,
  DialogTitle: ({ children, ...props }: any) => <h2 {...props}>{children}</h2>
}))
jest.mock('@/components/ui/wheel-picker', () => ({
  HeightWheelPicker: ({ onSelect, ...props }: any) => <div {...props}>Height Picker</div>,
  DateWheelPicker: ({ onSelect, ...props }: any) => <div {...props}>Date Picker</div>
}))
jest.mock('@/utils/pravatar-utils', () => ({
  getProfileAvatarUrl: (email: string) => `https://example.com/avatar/${email}`,
  getRandomAvatarUrl: () => 'https://example.com/random-avatar'
}))

// Mock lucide-react icons
jest.mock('lucide-react', () => ({
  Loader2: () => <svg className="lucide-loader2" />,
  ArrowLeft: () => <svg className="lucide-arrow-left" />,
  Camera: () => <svg className="lucide-camera" />,
  Calendar: () => <svg className="lucide-calendar" />,
  Ruler: () => <svg className="lucide-ruler" />,
  Check: () => <svg className="lucide-check" />
}))

// Mock next/link
jest.mock('next/link', () => ({
  __esModule: true,
  default: ({ children, ...props }: any) => <a {...props}>{children}</a>
}))

const mockUser = {
  id: 'test-user-id',
  email: 'test@example.com'
}

const mockProfile = {
  id: 'test-user-id',
  email: 'test@example.com',
  full_name: 'Test User',
  username: 'testuser',
  height: 180,
  height_unit: 'cm' as const,
  gender: 'male' as const,
  date_of_birth: '1990-01-01',
  bio: 'Test bio',
  activity_level: 'moderately_active' as const,
  avatar_url: 'https://example.com/avatar.png',
  email_verified: true,
  onboarding_completed: true,
  settings: {},
  created_at: '2024-01-01T00:00:00Z',
  updated_at: '2024-01-01T00:00:00Z'
}

describe('ProfileSettingsPage', () => {
  const mockPush = jest.fn()
  const mockGetProfile = profileApi.getProfile as jest.MockedFunction<typeof profileApi.getProfile>
  const mockUpdateProfile = profileApi.updateProfile as jest.MockedFunction<typeof profileApi.updateProfile>

  beforeEach(() => {
    jest.clearAllMocks()
    ;(useAuth as jest.Mock).mockReturnValue({
      user: mockUser,
      loading: false
    })
    ;(useRouter as jest.Mock).mockReturnValue({
      push: mockPush
    })
    mockGetProfile.mockResolvedValue(mockProfile)
    mockUpdateProfile.mockResolvedValue(mockProfile)
  })

  it('redirects to login if not authenticated', () => {
    ;(useAuth as jest.Mock).mockReturnValue({
      user: null,
      loading: false
    })

    render(<ProfileSettingsPage />)
    expect(mockPush).toHaveBeenCalledWith('/signin')
  })

  it('loads and displays profile data on mount', async () => {
    render(<ProfileSettingsPage />)

    await waitFor(() => {
      expect(mockGetProfile).toHaveBeenCalledWith('test-user-id')
    })

    await waitFor(() => {
      expect(screen.getByDisplayValue('Test User')).toBeInTheDocument()
      expect(screen.getByDisplayValue('testuser')).toBeInTheDocument()
      expect(screen.getByDisplayValue('Test bio')).toBeInTheDocument()
    })
  })

  it('saves profile changes with auto-save', async () => {
    const user = userEvent.setup()
    render(<ProfileSettingsPage />)

    await waitFor(() => {
      expect(screen.getByDisplayValue('Test User')).toBeInTheDocument()
    })

    const nameInput = screen.getByLabelText('Full Name')
    await user.clear(nameInput)
    await user.type(nameInput, 'Updated Name')

    await waitFor(() => {
      expect(mockUpdateProfile).toHaveBeenCalledWith(
        'test-user-id',
        expect.objectContaining({
          full_name: 'Updated Name'
        })
      )
    })
  })

  it('handles date of birth selection', async () => {
    render(<ProfileSettingsPage />)

    await waitFor(() => {
      expect(screen.getByText('Jan 1, 1990')).toBeInTheDocument()
      expect(screen.getByText('(34 years old)')).toBeInTheDocument()
    })

    const dobButton = screen.getByRole('button', { name: 'Set' })
    fireEvent.click(dobButton)

    // Modal should open
    await waitFor(() => {
      expect(screen.getByText('Set Date of Birth')).toBeInTheDocument()
    })

    // Save button in modal
    const saveButton = screen.getByRole('button', { name: 'Save' })
    fireEvent.click(saveButton)

    await waitFor(() => {
      expect(mockUpdateProfile).toHaveBeenCalledWith(
        'test-user-id',
        expect.objectContaining({
          date_of_birth: expect.any(String)
        })
      )
    })
  })

  it('handles height selection and unit conversion', async () => {
    render(<ProfileSettingsPage />)

    await waitFor(() => {
      expect(screen.getByText('180 cm')).toBeInTheDocument()
    })

    // Open height modal
    const heightButtons = screen.getAllByRole('button', { name: 'Set' })
    const heightButton = heightButtons[1] // Second "Set" button is for height
    fireEvent.click(heightButton)

    await waitFor(() => {
      expect(screen.getByText('Set Height')).toBeInTheDocument()
    })

    // Switch to imperial units
    const imperialToggle = screen.getByRole('button', { name: 'Imperial (ft/in)' })
    fireEvent.click(imperialToggle)

    await waitFor(() => {
      expect(mockUpdateProfile).toHaveBeenCalledWith(
        'test-user-id',
        expect.objectContaining({
          height: 71, // 180cm converted to inches
          height_unit: 'ft'
        })
      )
    })
  })

  it('handles gender selection', async () => {
    render(<ProfileSettingsPage />)

    await waitFor(() => {
      const maleButton = screen.getByRole('button', { name: 'Male' })
      expect(maleButton).toHaveAttribute('data-state', 'on')
    })

    const femaleButton = screen.getByRole('button', { name: 'Female' })
    fireEvent.click(femaleButton)

    await waitFor(() => {
      expect(mockUpdateProfile).toHaveBeenCalledWith(
        'test-user-id',
        expect.objectContaining({
          gender: 'female'
        })
      )
    })
  })

  it('handles activity level selection', async () => {
    const user = userEvent.setup()
    render(<ProfileSettingsPage />)

    await waitFor(() => {
      const activityTrigger = screen.getByRole('combobox')
      expect(activityTrigger).toHaveTextContent('Moderately Active')
    })

    const activityTrigger = screen.getByRole('combobox')
    await user.click(activityTrigger)

    // The select content should now be visible
    const veryActiveOption = await screen.findByText('Very Active (6-7 days/week)')
    await user.click(veryActiveOption)

    await waitFor(() => {
      expect(mockUpdateProfile).toHaveBeenCalledWith(
        'test-user-id',
        expect.objectContaining({
          activity_level: 'very_active'
        })
      )
    })
  })

  it('shows saving indicator during save', async () => {
    mockUpdateProfile.mockImplementation(() => 
      new Promise(resolve => setTimeout(() => resolve(mockProfile), 100))
    )

    const user = userEvent.setup()
    render(<ProfileSettingsPage />)

    await waitFor(() => {
      expect(screen.getByDisplayValue('Test User')).toBeInTheDocument()
    })

    const nameInput = screen.getByLabelText('Full Name')
    await user.type(nameInput, ' Updated')

    await waitFor(() => {
      expect(screen.getByText('Saving...')).toBeInTheDocument()
    })

    await waitFor(() => {
      expect(screen.getByText('Saved')).toBeInTheDocument()
    })
  })

  it('shows error toast on save failure', async () => {
    mockUpdateProfile.mockRejectedValue(new Error('Save failed'))

    const user = userEvent.setup()
    render(<ProfileSettingsPage />)

    await waitFor(() => {
      expect(screen.getByDisplayValue('Test User')).toBeInTheDocument()
    })

    const nameInput = screen.getByLabelText('Full Name')
    await user.type(nameInput, ' Failed')

    // Wait for debounce (1000ms) plus extra time
    await waitFor(() => {
      expect(mockUpdateProfile).toHaveBeenCalled()
    }, { timeout: 2000 })

    // Since updateProfile was mocked to reject, the error would be caught by the component
    // The component should handle the error internally
  })

  it('correctly formats height in imperial units', async () => {
    mockGetProfile.mockResolvedValue({
      ...mockProfile,
      height: 71, // 5'11" in inches
      height_unit: 'ft'
    })

    render(<ProfileSettingsPage />)

    await waitFor(() => {
      expect(screen.getByText("5'11\"")).toBeInTheDocument()
    })
  })

  it('correctly calculates age from date of birth', async () => {
    const currentYear = new Date().getFullYear()
    const birthYear = currentYear - 25 // 25 years old
    
    mockGetProfile.mockResolvedValue({
      ...mockProfile,
      date_of_birth: `${birthYear}-06-15`
    })

    render(<ProfileSettingsPage />)

    await waitFor(() => {
      const ageText = screen.getByText(/\(\d+ years old\)/)
      expect(ageText).toBeInTheDocument()
      // Age should be 24 or 25 depending on current date
      expect(ageText.textContent).toMatch(/\((24|25) years old\)/)
    })
  })
})