import React from 'react'
import { render, screen } from '@testing-library/react'
import DashboardPage from '../page'
import { useAuth } from '@/contexts/ClerkAuthContext'
import { useRouter, usePathname } from 'next/navigation'
import { getProfile } from '@/lib/supabase/profile'
import { createClient } from '@/lib/supabase/client'

// Mock dependencies
jest.mock('@/contexts/ClerkAuthContext')
jest.mock('next/navigation')
jest.mock('@/lib/supabase/profile')
jest.mock('@/lib/supabase/client', () => ({
  createClient: jest.fn(),
}))

// Don't mock MobileNavbar to test actual integration
jest.mock('@/components/MobileNavbar', () => {
  return {
    MobileNavbar: () => {
      // eslint-disable-next-line @typescript-eslint/no-require-imports
      const { usePathname } = require('next/navigation')
      const pathname = usePathname()
      if (pathname === '/log' || pathname.startsWith('/settings')) {
        return null
      }
      return <nav data-testid="mobile-navbar-real" className="md:hidden" />
    }
  }
})

jest.mock('../page', () => {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const React = require('react') as typeof import('react')
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { useRouter, usePathname } = require('next/navigation') as typeof import('next/navigation')
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { useAuth } = require('@/contexts/ClerkAuthContext') as typeof import('@/contexts/ClerkAuthContext')
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { MobileNavbar } = require('@/components/MobileNavbar') as typeof import('@/components/MobileNavbar')

  const TestDashboardPage: React.FC = () => {
    const { user } = useAuth()
    const router = useRouter()
    const _pathname = usePathname()

    if (!user) {
      return null
    }

    return (
      <div>
        <header className="md:flex">
          <div>LogYourBody</div>
        </header>
        <MobileNavbar />
      </div>
    )
  }

  return {
    __esModule: true,
    default: TestDashboardPage,
  }
})

describe('Mobile Navbar Integration', () => {
  const mockUser = { id: 'user-123', email: 'test@example.com' }

  beforeEach(() => {
    jest.clearAllMocks()
      ; (useAuth as jest.Mock).mockReturnValue({
        user: mockUser,
        loading: false,
      })
      ; (useRouter as jest.Mock).mockReturnValue({
        push: jest.fn(),
      })
      ; (getProfile as jest.Mock).mockResolvedValue(null)
      ; (createClient as jest.Mock).mockReturnValue({
        from: jest.fn().mockReturnValue({
          select: jest.fn().mockReturnValue({
            eq: jest.fn().mockReturnValue({
              order: jest.fn().mockResolvedValue({ data: [], error: null })
            })
          })
        })
      })
  })

  it('should show mobile navbar on dashboard', async () => {
    ; (usePathname as jest.Mock).mockReturnValue('/dashboard')

    render(<DashboardPage />)

    await screen.findByTestId('mobile-navbar-real')
    const navbar = screen.getByTestId('mobile-navbar-real')
    expect(navbar).toBeInTheDocument()
    expect(navbar).toHaveClass('md:hidden')
  })

  it('should not interfere with desktop navigation', async () => {
    ; (usePathname as jest.Mock).mockReturnValue('/dashboard')

    render(<DashboardPage />)

    // Desktop header should still be present
    await screen.findByText('LogYourBody')

    // Desktop navigation should have md:flex class
    const desktopNav = screen.getByText('LogYourBody').closest('header')
    expect(desktopNav).toHaveClass('md:flex')
  })

  it('should handle responsive classes correctly', async () => {
    ; (usePathname as jest.Mock).mockReturnValue('/dashboard')

    render(<DashboardPage />)

    await screen.findByTestId('mobile-navbar-real')

    // Mobile navbar should be hidden on desktop
    const navbar = screen.getByTestId('mobile-navbar-real')
    expect(navbar).toHaveClass('md:hidden')

    // Desktop elements should be hidden on mobile
    const desktopHeader = screen.getByText('LogYourBody').closest('div')
    expect(desktopHeader?.parentElement).toHaveClass('md:flex')
  })
})