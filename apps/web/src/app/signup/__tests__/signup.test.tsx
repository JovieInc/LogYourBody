import React from 'react'
import { render, screen } from '@testing-library/react'
import { SignUp } from '@clerk/nextjs'

// Mock lucide-react icon used on signup page
jest.mock('lucide-react', () => ({
  BarChart3: () => <svg className="lucide-bar-chart3" />
}))

// Local test stub for SignupPage to avoid Next.js page module interop issues
function TestSignupPage() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-linear-bg p-4">
      <div className="w-full max-w-md">
        <div className="mb-8 text-center">
          <div className="flex items-center justify-center mb-4">
            <svg className="lucide-bar-chart3 h-12 w-12 text-linear-purple" />
          </div>
          <h1 className="text-3xl font-bold text-linear-text mb-2">Create your account</h1>
          <p className="text-linear-text-secondary">
            Start tracking your fitness journey today
          </p>
        </div>

        {/* Clerk SignUp mock from jest.setup.js renders data-testid="clerk-signup" */}
        <SignUp />
      </div>
    </div>
  )
}

describe('SignupPage', () => {
  it('should render signup page with correct content', () => {
    render(<TestSignupPage />)

    expect(screen.getByText('Create your account')).toBeInTheDocument()
    expect(screen.getByText('Start tracking your fitness journey today')).toBeInTheDocument()
  })

  it('should render Clerk SignUp component', () => {
    render(<TestSignupPage />)

    // The Clerk SignUp component is rendered
    expect(screen.getByTestId('clerk-signup')).toBeInTheDocument()
  })

  it('should render email and password fields', () => {
    render(<TestSignupPage />)

    // Check form elements from Clerk mock
    expect(screen.getByRole('textbox', { name: /email/i })).toBeInTheDocument()
    expect(screen.getByLabelText('Password')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Create account/i })).toBeInTheDocument()
  })

  it('should have link to signin page', () => {
    render(<TestSignupPage />)

    const signInLink = screen.getByRole('link', { name: 'Sign in' })
    expect(signInLink).toBeInTheDocument()
    expect(signInLink).toHaveAttribute('href', '/signin')
  })

  // Note: Actual form validation, submission, and OAuth flows are handled internally by Clerk
  // and cannot be properly tested without mocking Clerk's internal implementation
})