import React from 'react'
import { render, screen } from '@testing-library/react'
import LoginPage from '../../signin/page'

// Mock lucide-react icon
jest.mock('lucide-react', () => ({
  BarChart3: () => <svg className="lucide-bar-chart3" />
}))

describe('LoginPage', () => {
  it('should render login page with correct content', () => {
    render(<LoginPage />)

    expect(screen.getByText('Welcome back')).toBeInTheDocument()
    expect(screen.getByText('Sign in to continue your fitness journey')).toBeInTheDocument()
  })

  it('should render Clerk SignIn component', () => {
    render(<LoginPage />)
    
    // The Clerk SignIn component is rendered
    expect(screen.getByTestId('clerk-signin')).toBeInTheDocument()
  })

  it('should render email and password fields', () => {
    render(<LoginPage />)
    
    // Check form elements from Clerk mock
    expect(screen.getByRole('textbox', { name: /email/i })).toBeInTheDocument()
    expect(screen.getByLabelText('Password')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Sign in/i })).toBeInTheDocument()
  })

  it('should have link to sign up page', () => {
    render(<LoginPage />)

    const signUpLink = screen.getByRole('link', { name: 'Sign up' })
    expect(signUpLink).toBeInTheDocument()
    expect(signUpLink).toHaveAttribute('href', '/signup')
  })

  it('should have link to forgot password page', () => {
    render(<LoginPage />)

    const forgotPasswordLink = screen.getByRole('link', { name: 'Forgot?' })
    expect(forgotPasswordLink).toBeInTheDocument()
    expect(forgotPasswordLink).toHaveAttribute('href', '/forgot-password')
  })

  // Note: Actual form validation, submission, and OAuth flows are handled internally by Clerk
  // and cannot be properly tested without mocking Clerk's internal implementation
})