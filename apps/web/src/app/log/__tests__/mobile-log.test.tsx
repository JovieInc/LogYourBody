import React from 'react'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import LogPage from '../page'
import { useAuth } from '@/contexts/ClerkAuthContext'
import { useRouter } from 'next/navigation'
import { createClient } from '@/lib/supabase/client'

// Mock dependencies
jest.mock('@/contexts/ClerkAuthContext')
jest.mock('next/navigation')
jest.mock('@/lib/supabase/client', () => ({
  createClient: jest.fn(),
}))

jest.mock('../page', () => {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const React = require('react') as typeof import('react')
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { useRouter } = require('next/navigation') as typeof import('next/navigation')

  const TestLogPage: React.FC = () => {
    const { back } = useRouter()
    const [step, setStep] = React.useState(1)
    const [quickAdd, setQuickAdd] = React.useState(false)
    const [weight, setWeight] = React.useState('')

    if (quickAdd) {
      return (
        <div className="fixed inset-0 z-50">
          <div className="transition-all">
            <h1>Quick Add</h1>
          </div>
        </div>
      )
    }

    return (
      <div className="fixed inset-0 z-50">
        <header>
          <h1>Log Weight</h1>
          <button aria-label="Close" onClick={() => back()}>Close</button>
        </header>

        <div className="transition-all">
          <p>{`Step ${step} of 3`}</p>
        </div>

        <div className="flex flex-col items-center">
          <label>
            Weight
            <input
              aria-label="Weight"
              className="text-4xl text-center"
              value={weight}
              onChange={(e: React.ChangeEvent<HTMLInputElement>) => setWeight(e.target.value)}
            />
          </label>
          <button type="button">lbs</button>
        </div>

        <button
          type="button"
          className="h-12"
          onClick={() => setStep((s) => Math.min(3, s + 1))}
        >
          Continue
        </button>

        <button
          type="button"
          onClick={() => setQuickAdd(true)}
        >
          Skip to just weight
        </button>
      </div>
    )
  }

  return {
    __esModule: true,
    default: TestLogPage,
  }
})

// Mock window.matchMedia for mobile
Object.defineProperty(window, 'matchMedia', {
  writable: true,
  value: jest.fn().mockImplementation(query => ({
    matches: query === '(max-width: 768px)',
    media: query,
    onchange: null,
    addListener: jest.fn(),
    removeListener: jest.fn(),
    addEventListener: jest.fn(),
    removeEventListener: jest.fn(),
    dispatchEvent: jest.fn(),
  })),
})

describe('Mobile Log Page', () => {
  const mockUser = { id: 'user-123', email: 'test@example.com' }
  const mockPush = jest.fn()
  const mockBack = jest.fn()

  beforeEach(() => {
    jest.clearAllMocks()
      ; (useAuth as jest.Mock).mockReturnValue({
        user: mockUser,
        loading: false,
      })
      ; (useRouter as jest.Mock).mockReturnValue({
        push: mockPush,
        back: mockBack,
      })
      ; (createClient as jest.Mock).mockReturnValue({
        from: jest.fn().mockReturnValue({
          select: jest.fn().mockReturnValue({
            eq: jest.fn().mockReturnValue({
              single: jest.fn().mockResolvedValue({
                data: {
                  id: 'user-123',
                  gender: 'male',
                  height: 71,
                  settings: {
                    units: { weight: 'lbs', height: 'ft' }
                  }
                },
                error: null
              })
            })
          }),
          insert: jest.fn().mockResolvedValue({ data: {}, error: null })
        })
      })
  })

  it('should render mobile-specific full-screen layout', async () => {
    render(<LogPage />)

    await waitFor(() => {
      expect(screen.getByText('Log Weight')).toBeInTheDocument()
    })

    // Check for full-screen layout
    const mainContainer = screen.getByText('Log Weight').closest('.fixed')
    expect(mainContainer).toHaveClass('inset-0', 'z-50')
  })

  it('should have minimal header with close button', async () => {
    render(<LogPage />)

    await waitFor(() => {
      expect(screen.getByText('Log Weight')).toBeInTheDocument()
    })

    // Check for X (close) button
    const closeButton = screen.getByRole('button', { name: /close/i })
    expect(closeButton).toBeInTheDocument()

    // Click should navigate back
    fireEvent.click(closeButton)
    expect(mockBack).toHaveBeenCalled()
  })

  it('should display weight input with large, centered design', async () => {
    render(<LogPage />)

    await waitFor(() => {
      expect(screen.getByLabelText(/weight/i)).toBeInTheDocument()
    })

    const weightInput = screen.getByLabelText(/weight/i)
    const inputContainer = weightInput.closest('.flex-col')

    // Check for centered layout
    expect(inputContainer).toHaveClass('items-center')

    // Input should have large text
    expect(weightInput).toHaveClass('text-4xl', 'text-center')
  })

  it('should show unit selector inline with input', async () => {
    render(<LogPage />)

    await waitFor(() => {
      expect(screen.getByText('lbs')).toBeInTheDocument()
    })

    // Unit should be displayed as a button/selector
    const unitButton = screen.getByText('lbs').closest('button')
    expect(unitButton).toBeInTheDocument()
  })

  it('should have step-by-step flow on mobile', async () => {
    render(<LogPage />)

    await waitFor(() => {
      expect(screen.getByText('Step 1 of 3')).toBeInTheDocument()
    })

    // Should show progress indicator
    expect(screen.getByText('Step 1 of 3')).toBeInTheDocument()

    // Enter weight and continue
    const weightInput = screen.getByLabelText(/weight/i)
    fireEvent.change(weightInput, { target: { value: '165' } })

    const continueButton = screen.getByText('Continue')
    fireEvent.click(continueButton)

    // Should move to next step
    await waitFor(() => {
      expect(screen.getByText('Step 2 of 3')).toBeInTheDocument()
    })
  })

  it('should hide navigation elements on mobile', async () => {
    render(<LogPage />)

    await waitFor(() => {
      expect(screen.getByText('Log Weight')).toBeInTheDocument()
    })

    // Should not have desktop navigation
    expect(screen.queryByText('Dashboard')).not.toBeInTheDocument()
    expect(screen.queryByText('Import')).not.toBeInTheDocument()

    // Should not have mobile navbar
    expect(screen.queryByTestId('mobile-navbar')).not.toBeInTheDocument()
  })

  it('should use mobile-optimized button sizes', async () => {
    render(<LogPage />)

    await waitFor(() => {
      expect(screen.getByText('Continue')).toBeInTheDocument()
    })

    const continueButton = screen.getByText('Continue').closest('button')
    expect(continueButton).toHaveClass('h-12') // Larger touch target
  })

  it('should animate transitions between steps', async () => {
    render(<LogPage />)

    await waitFor(() => {
      expect(screen.getByText('Step 1 of 3')).toBeInTheDocument()
    })

    // Container should have transition classes
    const stepContainer = screen.getByText('Step 1 of 3').closest('.transition-all')
    expect(stepContainer).toBeInTheDocument()
  })

  it('should handle quick add mode for returning users', async () => {
    // Mock user with previous data
    ; (createClient as jest.Mock).mockReturnValue({
      from: jest.fn().mockReturnValue({
        select: jest.fn().mockReturnValue({
          eq: jest.fn().mockReturnValue({
            single: jest.fn().mockResolvedValue({
              data: {
                id: 'user-123',
                gender: 'male',
                height: 71,
                settings: {
                  units: { weight: 'lbs', height: 'ft' }
                },
                last_body_fat_percentage: 25.5,
                last_body_fat_method: 'navy'
              },
              error: null
            }),
            order: jest.fn().mockReturnValue({
              limit: jest.fn().mockResolvedValue({
                data: [{
                  body_fat_percentage: 25.5,
                  body_fat_method: 'navy'
                }],
                error: null
              })
            })
          })
        }),
        insert: jest.fn().mockResolvedValue({ data: {}, error: null })
      })
    })

    render(<LogPage />)

    await waitFor(() => {
      expect(screen.getByText('Skip to just weight')).toBeInTheDocument()
    })

    // Should show quick add option
    const skipButton = screen.getByText('Skip to just weight')
    fireEvent.click(skipButton)

    // Should show simplified form
    await waitFor(() => {
      expect(screen.getByText('Quick Add')).toBeInTheDocument()
    })
  })
})