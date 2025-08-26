import React from 'react'
import { render, screen } from '@testing-library/react'
import SignupPage from '../page'

// Mock lucide-react icon
jest.mock('lucide-react', () => ({
  BarChart3: () => <svg className="lucide-bar-chart3" />
}))

describe('SignupPage', () => {
  it('should render signup page with correct content', () => {
    render(<SignupPage />)

    expect(screen.getByText('Create your account')).toBeInTheDocument()
    expect(screen.getByText('Start tracking your fitness journey today')).toBeInTheDocument()
  })

  it('should render Clerk SignUp component', () => {
    render(<SignupPage />)
    
    // The Clerk SignUp component is rendered
    expect(screen.getByTestId('clerk-signup')).toBeInTheDocument()
  })

  it('should render email and password fields', () => {
    render(<SignupPage />)
    
    // Check form elements from Clerk mock
    expect(screen.getByRole('textbox', { name: /email/i })).toBeInTheDocument()
    expect(screen.getByLabelText('Password')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /Create account/i })).toBeInTheDocument()
  })

  it('should have link to signin page', () => {
    render(<SignupPage />)

    const signInLink = screen.getByRole('link', { name: 'Sign in' })
    expect(signInLink).toBeInTheDocument()
    expect(signInLink).toHaveAttribute('href', '/signin')
  })

  // Note: Actual form validation, submission, and OAuth flows are handled internally by Clerk
  // and cannot be properly tested without mocking Clerk's internal implementation
})