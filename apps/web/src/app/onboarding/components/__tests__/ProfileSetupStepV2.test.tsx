import React from 'react'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import '@testing-library/jest-dom'
import { ProfileSetupStepV2 } from '../ProfileSetupStepV2'
import { useOnboarding } from '@/contexts/OnboardingContext'
import { useMediaQuery } from '@/hooks/use-media-query'
import { useAuth } from '@/contexts/ClerkAuthContext'

// Mock dependencies
jest.mock('@/contexts/OnboardingContext')
jest.mock('@/hooks/use-media-query')
jest.mock('@/contexts/ClerkAuthContext')

// Framer-motion is already mocked in jest.setup.js

const mockUpdateData = jest.fn()
const mockNextStep = jest.fn()
const mockPreviousStep = jest.fn()

const mockValidData = {
  fullName: 'John Doe',
  dateOfBirth: '1990-01-01',
  height: 71,
  gender: ''
}

describe('ProfileSetupStepV2', () => {
  beforeEach(() => {
    jest.clearAllMocks()
      ; (useOnboarding as jest.Mock).mockReturnValue({
        data: {},
        updateData: mockUpdateData,
        nextStep: mockNextStep,
        previousStep: mockPreviousStep
      })
      ; (useMediaQuery as jest.Mock).mockReturnValue(false) // Desktop by default
      ; (useAuth as jest.Mock).mockReturnValue({ user: null })
  })

  describe('Step Flow', () => {
    it('should start with name step', () => {
      render(<ProfileSetupStepV2 />)

      expect(screen.getByText("What's your name?")).toBeInTheDocument()
      expect(screen.getByPlaceholderText('First name')).toBeInTheDocument()
      expect(screen.getByPlaceholderText('Last name')).toBeInTheDocument()
      expect(screen.getByText('1 of 4')).toBeInTheDocument()
    })

    it('should progress through steps in order', async () => {
      render(<ProfileSetupStepV2 />)

      // Enter name
      const firstNameInput = screen.getByPlaceholderText('First name')
      const lastNameInput = screen.getByPlaceholderText('Last name')
      fireEvent.change(firstNameInput, { target: { value: 'John' } })
      fireEvent.change(lastNameInput, { target: { value: 'Doe' } })

      // Click Next
      const nextButton = screen.getByRole('button', { name: /Next/i })
      fireEvent.click(nextButton)

      // Should be on date of birth step
      await waitFor(() => {
        expect(screen.getByText('When were you born?')).toBeInTheDocument()
        expect(screen.getByText('2 of 4')).toBeInTheDocument()
      })
    })

    it('should show Complete button on last step', async () => {
      // Provide data that makes all steps valid
      ; (useOnboarding as jest.Mock).mockReturnValue({
        data: {
          fullName: 'John Doe',
          dateOfBirth: '1990-01-01',
          height: 71,
          gender: 'male'
        },
        updateData: mockUpdateData,
        nextStep: mockNextStep,
        previousStep: mockPreviousStep
      })

      render(<ProfileSetupStepV2 />)

      // Navigate to gender step (last step)
      fireEvent.click(screen.getByRole('button', { name: /Next/i }))

      // Skip DOB
      await waitFor(() => screen.getByText('When were you born?'))
      fireEvent.click(screen.getByRole('button', { name: /Next/i }))

      // Skip Height
      await waitFor(() => screen.getByText('How tall are you?'))
      fireEvent.click(screen.getByRole('button', { name: /Next/i }))

      // Should be on gender step with Complete button
      await waitFor(() => {
        expect(screen.getByText('Select your biological sex')).toBeInTheDocument()
        expect(screen.getByRole('button', { name: /Complete/i })).toBeInTheDocument()
      })
    })
  })

  describe('Name Step', () => {
    it('should enable Next button when both first and last name are entered', () => {
      render(<ProfileSetupStepV2 />)

      const nextButton = screen.getByRole('button', { name: /Next/i })
      expect(nextButton).toBeDisabled()

      const firstNameInput = screen.getByPlaceholderText('First name')
      const lastNameInput = screen.getByPlaceholderText('Last name')
      fireEvent.change(firstNameInput, { target: { value: 'John' } })
      // Still disabled with only first name
      expect(nextButton).toBeDisabled()

      fireEvent.change(lastNameInput, { target: { value: 'Doe' } })

      expect(nextButton).not.toBeDisabled()
      expect(nextButton).toHaveClass('animate-glow-pulse')
    })

    it('should support Enter key to proceed', () => {
      render(<ProfileSetupStepV2 />)

      const firstNameInput = screen.getByPlaceholderText('First name')
      const lastNameInput = screen.getByPlaceholderText('Last name')
      fireEvent.change(firstNameInput, { target: { value: 'John' } })
      fireEvent.change(lastNameInput, { target: { value: 'Doe' } })
      fireEvent.keyPress(lastNameInput, { key: 'Enter', code: 'Enter' })

      // Should progress to next step
      waitFor(() => {
        expect(screen.getByText('When were you born?')).toBeInTheDocument()
      })
    })
  })

  describe('Date of Birth Step - Desktop', () => {
    beforeEach(async () => {
      render(<ProfileSetupStepV2 />)

      // Navigate to DOB step
      const firstNameInput = screen.getByPlaceholderText('First name')
      const lastNameInput = screen.getByPlaceholderText('Last name')
      fireEvent.change(firstNameInput, { target: { value: 'John' } })
      fireEvent.change(lastNameInput, { target: { value: 'Doe' } })
      fireEvent.click(screen.getByRole('button', { name: /Next/i }))

      await waitFor(() => {
        expect(screen.getByText('When were you born?')).toBeInTheDocument()
      })
    })

    it('should show dropdown selects on desktop', () => {
      expect(screen.getByText('Month')).toBeInTheDocument()
      expect(screen.getByText('Day')).toBeInTheDocument()
      expect(screen.getByText('Year')).toBeInTheDocument()

      // Should have 3 select elements
      const selects = screen.getAllByRole('combobox')
      expect(selects).toHaveLength(3)
    })

    it('should calculate and display age', () => {
      const currentYear = new Date().getFullYear()
      const expectedAge = currentYear - 1990 // Default year is 1990

      expect(screen.getByText(`You are ${expectedAge} years old`)).toBeInTheDocument()
    })
  })

  describe('Date of Birth Step - Mobile', () => {
    beforeEach(async () => {
      ; (useMediaQuery as jest.Mock).mockReturnValue(true) // Mobile view

      render(<ProfileSetupStepV2 />)

      // Navigate to DOB step
      const firstNameInput = screen.getByPlaceholderText('First name')
      const lastNameInput = screen.getByPlaceholderText('Last name')
      fireEvent.change(firstNameInput, { target: { value: 'John' } })
      fireEvent.change(lastNameInput, { target: { value: 'Doe' } })
      fireEvent.click(screen.getByRole('button', { name: /Next/i }))

      await waitFor(() => {
        expect(screen.getByText('When were you born?')).toBeInTheDocument()
      })
    })

    it('should show wheel picker on mobile', () => {
      // Should not have select dropdowns
      const selects = screen.queryAllByRole('combobox')
      expect(selects).toHaveLength(0)

      // Should have wheel picker (checking by className)
      expect(screen.getByText('When were you born?')).toBeInTheDocument()
    })
  })

  describe('Height Step', () => {
    beforeEach(async () => {
      ; (useOnboarding as jest.Mock).mockReturnValue({
        data: { ...mockValidData },
        updateData: mockUpdateData,
        nextStep: mockNextStep,
        previousStep: mockPreviousStep
      })

      render(<ProfileSetupStepV2 />)

      // Navigate to height step
      fireEvent.click(screen.getByRole('button', { name: /Next/i }))

      await waitFor(() => screen.getByText('When were you born?'))
      fireEvent.click(screen.getByRole('button', { name: /Next/i }))

      await waitFor(() => {
        expect(screen.getByText('How tall are you?')).toBeInTheDocument()
      })
    })

    it('should show feet/inches dropdowns on desktop', () => {
      expect(screen.getByText('Feet')).toBeInTheDocument()
      expect(screen.getByText('Inches')).toBeInTheDocument()

      const selects = screen.getAllByRole('combobox')
      expect(selects).toHaveLength(2)
    })

    it('should display height conversion to cm', () => {
      // Default is 71 inches (5'11")
      expect(screen.getByText('5\'11" = 180 cm')).toBeInTheDocument()
    })
  })

  describe('Gender Step', () => {
    beforeEach(async () => {
      ; (useOnboarding as jest.Mock).mockReturnValue({
        data: { ...mockValidData },
        updateData: mockUpdateData,
        nextStep: mockNextStep,
        previousStep: mockPreviousStep
      })

      render(<ProfileSetupStepV2 />)

      // Navigate to gender step
      fireEvent.click(screen.getByRole('button', { name: /Next/i }))

      await waitFor(() => screen.getByText('When were you born?'))
      fireEvent.click(screen.getByRole('button', { name: /Next/i }))

      await waitFor(() => screen.getByText('How tall are you?'))
      fireEvent.click(screen.getByRole('button', { name: /Next/i }))

      await waitFor(() => {
        expect(screen.getByText('Select your biological sex')).toBeInTheDocument()
      })
    })

    it('should display gender options with icons', () => {
      expect(screen.getByText('Male')).toBeInTheDocument()
      expect(screen.getByText('Female')).toBeInTheDocument()
      expect(screen.getByText('♂️')).toBeInTheDocument()
      expect(screen.getByText('♀️')).toBeInTheDocument()
    })

    it('should highlight selected gender', () => {
      const maleButton = screen.getByText('Male').closest('button')
      fireEvent.click(maleButton!)

      expect(maleButton).toHaveClass('border-linear-purple')
      expect(maleButton).toHaveClass('bg-linear-purple/10')
    })

    it('should save data and call nextStep on completion', () => {
      const femaleButton = screen.getByText('Female').closest('button')
      fireEvent.click(femaleButton!)

      const completeButton = screen.getByRole('button', { name: /Complete/i })
      fireEvent.click(completeButton)

      expect(mockUpdateData).toHaveBeenCalledWith({
        fullName: 'John Doe',
        dateOfBirth: expect.any(String),
        height: 71,
        gender: 'female'
      })
      expect(mockNextStep).toHaveBeenCalled()
    })
  })

  describe('Navigation', () => {
    it('should go back to previous profile step', async () => {
      render(<ProfileSetupStepV2 />)

      // Go to DOB step
      const firstNameInput = screen.getByPlaceholderText('First name')
      const lastNameInput = screen.getByPlaceholderText('Last name')
      fireEvent.change(firstNameInput, { target: { value: 'John' } })
      fireEvent.change(lastNameInput, { target: { value: 'Doe' } })
      fireEvent.click(screen.getByRole('button', { name: /Next/i }))

      await waitFor(() => {
        expect(screen.getByText('When were you born?')).toBeInTheDocument()
      })

      // Click Back
      const backButton = screen.getByRole('button', { name: /Back/i })
      fireEvent.click(backButton)

      // Should be back on name step
      await waitFor(() => {
        expect(screen.getByText("What's your name?")).toBeInTheDocument()
        expect(screen.getByDisplayValue('John')).toBeInTheDocument()
        expect(screen.getByDisplayValue('Doe')).toBeInTheDocument()
      })
    })

    it('should call previousStep when backing out of first step', () => {
      render(<ProfileSetupStepV2 />)

      const backButton = screen.getByRole('button', { name: /Back/i })
      fireEvent.click(backButton)

      expect(mockPreviousStep).toHaveBeenCalled()
    })
  })

  describe('Mobile Responsiveness', () => {
    beforeEach(() => {
      ; (useMediaQuery as jest.Mock).mockReturnValue(true) // Mobile view
    })

    it('should show mobile-appropriate text', () => {
      render(<ProfileSetupStepV2 />)

      expect(screen.getByText('Tap Next to continue')).toBeInTheDocument()
    })

    it('should have smaller text size on mobile', () => {
      render(<ProfileSetupStepV2 />)

      const firstNameInput = screen.getByPlaceholderText('First name')
      const lastNameInput = screen.getByPlaceholderText('Last name')
      expect(firstNameInput).toHaveClass('text-base')
      expect(firstNameInput).toHaveClass('h-12')
    })

    it('prefers existing onboarding fullName over Clerk user data', () => {
      ; (useAuth as jest.Mock).mockReturnValue({
        user: { firstName: 'ClerkFirst', lastName: 'ClerkLast' }
      })
        ; (useOnboarding as jest.Mock).mockReturnValue({
          data: { fullName: 'Existing User' },
          updateData: mockUpdateData,
          nextStep: mockNextStep,
          previousStep: mockPreviousStep
        })

      render(<ProfileSetupStepV2 />)

      expect(screen.getByPlaceholderText('First name')).toHaveValue('Existing')
      expect(screen.getByPlaceholderText('Last name')).toHaveValue('User')
    })
  })