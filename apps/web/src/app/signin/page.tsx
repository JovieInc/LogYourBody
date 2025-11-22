'use client'

import { SignIn } from '@clerk/nextjs'
import { BarChart3, AlertCircle } from 'lucide-react'
import { useAuth } from '@/contexts/ClerkAuthContext'
import { Alert, AlertDescription } from '@/components/ui/alert'

export default function SignInPage() {
  const { exitReason } = useAuth()
  const showSessionExpired = exitReason === 'sessionExpired'
  return (
    <div className="min-h-screen flex items-center justify-center bg-linear-bg p-4">
      <div className="w-full max-w-md">
        <div className="mb-8 text-center">
          <div className="flex items-center justify-center mb-4">
            <BarChart3 className="h-12 w-12 text-linear-purple" />
          </div>
          <h1 className="text-3xl font-bold text-linear-text mb-2">Welcome back</h1>
          <p className="text-linear-text-secondary">
            Sign in to continue your fitness journey
          </p>
        </div>

        {showSessionExpired && (
          <div className="mb-4">
            <Alert className="bg-yellow-500/10 border-yellow-500/40 text-yellow-100">
              <AlertCircle className="h-4 w-4 mr-2" />
              <AlertDescription>
                <p className="font-medium">Session expired</p>
                <p className="text-sm text-yellow-100/80">
                  Your session ended. Please sign in again to continue.
                </p>
              </AlertDescription>
            </Alert>
          </div>
        )}

        <SignIn
          appearance={{
            baseTheme: undefined,
            variables: {
              colorPrimary: '#8b5cf6', // linear-purple
              colorText: '#e1e1e3', // linear-text
              colorTextSecondary: '#a1a1a8', // linear-text-secondary
              colorBackground: '#18181b', // linear-card
              colorInputBackground: '#18181b',
              colorInputText: '#e1e1e3',
              borderRadius: '0.5rem',
            },
            elements: {
              rootBox: 'mx-auto',
              card: 'bg-linear-card border-linear-border shadow-xl',
              headerTitle: 'hidden',
              headerSubtitle: 'hidden',
              socialButtonsBlockButton: 'border-linear-border hover:bg-linear-hover',
              formButtonPrimary: 'bg-linear-purple hover:bg-linear-purple/90',
              footerActionLink: 'text-linear-purple hover:text-linear-purple/80',
              identityPreviewEditButton: 'text-linear-purple hover:text-linear-purple/80',
              formFieldLabel: 'text-linear-text-secondary',
              formFieldInput: 'bg-linear-bg border-linear-border text-linear-text',
              dividerLine: 'bg-linear-border',
              dividerText: 'text-linear-text-tertiary',
              link: 'text-linear-purple hover:text-linear-purple/80',
              formFieldAction: 'text-linear-purple hover:text-linear-purple/80',
              footerAction: 'text-linear-text-secondary',
            }
          }}
          routing="path"
          path="/signin"
          signUpUrl="/signup"
          afterSignInUrl="/dashboard"
          forceRedirectUrl="/dashboard"
        />
      </div>
    </div>
  )
}