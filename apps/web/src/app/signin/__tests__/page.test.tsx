import '@testing-library/jest-dom'
import { render, screen } from '@testing-library/react'
import SignInPage from '../page'
import { useAuth } from '@/contexts/ClerkAuthContext'

jest.mock('@/contexts/ClerkAuthContext')
jest.mock('@clerk/nextjs', () => ({
    SignIn: () => <div data-testid="clerk-signin" />,
}))

describe('SignInPage', () => {
    beforeEach(() => {
        jest.clearAllMocks()
    })

    it('shows session expired banner when exitReason is sessionExpired', () => {
        ; (useAuth as jest.Mock).mockReturnValue({
            exitReason: 'sessionExpired',
        })

        render(<SignInPage />)

        expect(screen.getByText(/Session expired/i)).toBeInTheDocument()
        expect(
            screen.getByText(/Your session ended. Please sign in again to continue\./i)
        ).toBeInTheDocument()
    })

    it('does not show session banner when exitReason is none', () => {
        ; (useAuth as jest.Mock).mockReturnValue({
            exitReason: 'none',
        })

        render(<SignInPage />)

        expect(screen.queryByText(/Session expired/i)).not.toBeInTheDocument()
    })
})
