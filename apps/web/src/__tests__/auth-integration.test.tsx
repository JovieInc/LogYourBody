/**
 * Integration tests for authentication flow
 * These tests ensure our authentication system continues to work correctly
 */

import React from 'react'
import { render, screen } from '@testing-library/react'
import LoginPage from '@/app/signin/page'
import SignupPage from '@/app/signup/page'
import { AuthProvider } from '@/contexts/ClerkAuthContext'

// Mock lucide-react icon
jest.mock('lucide-react', () => ({
  BarChart3: () => <svg className="lucide-bar-chart3" />
}))

describe('Authentication Integration Tests', () => {
  beforeEach(() => {
    jest.clearAllMocks()
  })

  describe('Sign In Page', () => {
    it('should render sign in page with correct content', () => {
      render(
        <AuthProvider>
          <LoginPage />
        </AuthProvider>
      )

      expect(screen.getByText('Welcome back')).toBeInTheDocument()
      expect(screen.getByText('Sign in to continue your fitness journey')).toBeInTheDocument()
    })

    it('should render Clerk SignIn component', () => {
      render(
        <AuthProvider>
          <LoginPage />
        </AuthProvider>
      )
      
      // The Clerk SignIn component is rendered
      expect(screen.getByTestId('clerk-signin')).toBeInTheDocument()
    })

    it('should have correct form elements', () => {
      render(
        <AuthProvider>
          <LoginPage />
        </AuthProvider>
      )
      
      // Check form elements from Clerk mock
      expect(screen.getByRole('textbox', { name: /email/i })).toBeInTheDocument()
      expect(screen.getByLabelText('Password')).toBeInTheDocument()
      expect(screen.getByRole('button', { name: /Sign in/i })).toBeInTheDocument()
    })

    it('should have links to signup and forgot password', () => {
      render(
        <AuthProvider>
          <LoginPage />
        </AuthProvider>
      )

      const signUpLink = screen.getByRole('link', { name: 'Sign up' })
      expect(signUpLink).toBeInTheDocument()
      expect(signUpLink).toHaveAttribute('href', '/signup')

      const forgotLink = screen.getByRole('link', { name: 'Forgot?' })
      expect(forgotLink).toBeInTheDocument()
      expect(forgotLink).toHaveAttribute('href', '/forgot-password')
    })
  })

  describe('Sign Up Page', () => {
    it('should render sign up page with correct content', () => {
      render(
        <AuthProvider>
          <SignupPage />
        </AuthProvider>
      )

      expect(screen.getByText('Create your account')).toBeInTheDocument()
      expect(screen.getByText('Start tracking your fitness journey today')).toBeInTheDocument()
    })

    it('should render Clerk SignUp component', () => {
      render(
        <AuthProvider>
          <SignupPage />
        </AuthProvider>
      )
      
      // The Clerk SignUp component is rendered
      expect(screen.getByTestId('clerk-signup')).toBeInTheDocument()
    })
  })

  // Note: Actual authentication flows (sign in, sign up, OAuth, etc.) are handled internally by Clerk
  // and cannot be properly tested without mocking Clerk's internal implementation.
  // These tests verify that the pages render correctly and contain the expected Clerk components.
})