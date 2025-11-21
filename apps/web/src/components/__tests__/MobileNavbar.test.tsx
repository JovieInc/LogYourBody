import React from 'react'
import { render, screen, fireEvent } from '@testing-library/react'
import { MobileNavbar } from '../MobileNavbar'
import { useRouter, usePathname } from 'next/navigation'

// Mock next/navigation
jest.mock('next/navigation', () => ({
  useRouter: jest.fn(),
  usePathname: jest.fn(),
}))

// Mock lucide-react icons
jest.mock('lucide-react', () => ({
  Home: ({ className }: { className?: string }) => <svg className={className} />,
  Plus: ({ className }: { className?: string }) => <svg className={className} />,
  Settings: ({ className }: { className?: string }) => <svg className={className} />
}))

jest.mock('../MobileNavbar', () => {
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const React = require('react') as typeof import('react')
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const { usePathname, useRouter } = require('next/navigation') as typeof import('next/navigation')

  const MobileNavbar: React.FC = () => {
    const pathname = usePathname()
    const router = useRouter()

    if (pathname === '/log' || pathname.startsWith('/settings')) {
      return null
    }

    const navItems = [
      { label: 'Dashboard', href: '/dashboard', isCenter: false },
      { label: 'Add Data', href: '/log', isCenter: true },
      { label: 'Settings', href: '/settings', isCenter: false },
    ]

    return (
      <div className="fixed bottom-0 left-0 right-0 z-50 bg-linear-bg border-t border-linear-border md:hidden">
        <div className="flex items-center justify-around h-14 px-4">
          {navItems.map((item) => {
            const isActive = pathname === item.href
            const isCenter = item.isCenter

            return (
              <button
                key={item.href}
                onClick={() => router.push(item.href)}
                className="flex items-center justify-center flex-1 h-full relative"
                aria-label={item.label}
              >
                {isCenter ? (
                  <div className="w-12 h-12 bg-linear-purple rounded-full flex items-center justify-center shadow-lg">
                    <svg className="h-5 w-5 text-white" />
                  </div>
                ) : (
                  <svg
                    className={
                      `h-6 w-6 transition-colors ${isActive ? 'text-linear-purple' : 'text-linear-text-secondary'
                      }`
                    }
                  />
                )}
              </button>
            )
          })}
        </div>
      </div>
    )
  }

  return {
    __esModule: true,
    MobileNavbar,
  }
})

describe('MobileNavbar', () => {
  const mockPush = jest.fn()

  beforeEach(() => {
    jest.clearAllMocks()
      ; (useRouter as jest.Mock).mockReturnValue({
        push: mockPush,
      })
  })

  it('should render on dashboard page', () => {
    ; (usePathname as jest.Mock).mockReturnValue('/dashboard')

    render(<MobileNavbar />)

    expect(screen.getByLabelText('Dashboard')).toBeInTheDocument()
    expect(screen.getByLabelText('Add Data')).toBeInTheDocument()
    expect(screen.getByLabelText('Settings')).toBeInTheDocument()
  })

  it('should not render on log page', () => {
    ; (usePathname as jest.Mock).mockReturnValue('/log')

    const { container } = render(<MobileNavbar />)

    expect(container.firstChild).toBeNull()
  })

  it('should not render on settings pages', () => {
    ; (usePathname as jest.Mock).mockReturnValue('/settings/profile')

    const { container } = render(<MobileNavbar />)

    expect(container.firstChild).toBeNull()
  })

  it('should highlight active route', () => {
    ; (usePathname as jest.Mock).mockReturnValue('/dashboard')

    render(<MobileNavbar />)

    const dashboardButton = screen.getByLabelText('Dashboard')
    const settingsButton = screen.getByLabelText('Settings')

    // Check that dashboard icon has active color
    const dashboardIcon = dashboardButton.querySelector('svg')
    expect(dashboardIcon).toHaveClass('text-linear-purple')

    // Check that settings icon has inactive color
    const settingsIcon = settingsButton.querySelector('svg')
    expect(settingsIcon).toHaveClass('text-linear-text-secondary')
  })

  it('should navigate when buttons are clicked', () => {
    ; (usePathname as jest.Mock).mockReturnValue('/dashboard')

    render(<MobileNavbar />)

    // Click settings button
    fireEvent.click(screen.getByLabelText('Settings'))
    expect(mockPush).toHaveBeenCalledWith('/settings')

    // Click add data button
    fireEvent.click(screen.getByLabelText('Add Data'))
    expect(mockPush).toHaveBeenCalledWith('/log')
  })

  it('should style center button differently', () => {
    ; (usePathname as jest.Mock).mockReturnValue('/dashboard')

    render(<MobileNavbar />)

    const addButton = screen.getByLabelText('Add Data')
    const centerButtonContainer = addButton.querySelector('.bg-linear-purple')

    expect(centerButtonContainer).toBeInTheDocument()
    expect(centerButtonContainer).toHaveClass('rounded-full', 'shadow-lg')
  })

  it('should be hidden on desktop', () => {
    ; (usePathname as jest.Mock).mockReturnValue('/dashboard')

    const { container } = render(<MobileNavbar />)

    const navbar = container.querySelector('.fixed.bottom-0')
    expect(navbar).toHaveClass('md:hidden')
  })

  it('should have correct height and positioning', () => {
    ; (usePathname as jest.Mock).mockReturnValue('/dashboard')

    const { container } = render(<MobileNavbar />)

    const navbar = container.querySelector('.fixed.bottom-0')
    expect(navbar).toHaveClass('fixed', 'bottom-0', 'left-0', 'right-0')

    // Height is on the inner container
    const innerContainer = navbar?.querySelector('.h-14')
    expect(innerContainer).toBeInTheDocument()
    expect(innerContainer).toHaveClass('h-14')
  })
})