'use client'

import { useState, useEffect } from 'react'
import { useAuth } from '@/contexts/ClerkAuthContext'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { X, Mail, CheckCircle } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'

export function EmailConfirmationBanner() {
  const { user } = useAuth()
  const [isVisible, setIsVisible] = useState(false)
  const [isSending, setIsSending] = useState(false)
  const [lastSent, setLastSent] = useState<Date | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const supabase = createClient()

  useEffect(() => {
    // Check if user exists and email is not confirmed
    const checkEmailStatus = async () => {
      if (!user) {
        setIsVisible(false)
        return
      }

      // Get user profile to check email verification status
      const { data: profile } = await supabase
        .from('profiles')
        .select('email_verified')
        .eq('id', user.id)
        .single()

      setIsVisible(profile?.email_verified === false)
    }

    checkEmailStatus()
  }, [user, supabase])

  const handleResendEmail = async () => {
    const email = user?.primaryEmailAddress?.emailAddress
      ?? user?.emailAddresses?.[0]?.emailAddress
    if (!email || isSending) return

    // Check if we sent an email recently (within 60 seconds)
    if (lastSent && new Date().getTime() - lastSent.getTime() < 60000) {
      setMessage('Please wait a minute before requesting another email.')
      return
    }

    setIsSending(true)
    setMessage(null)

    try {
      const { error } = await supabase.auth.resend({
        type: 'signup',
        email,
      })

      if (error) throw error

      setLastSent(new Date())
      setMessage('Confirmation email sent! Please check your inbox.')
    } catch (error) {
      console.error('Error resending email:', error)
      setMessage('Failed to send email. Please try again later.')
    } finally {
      setIsSending(false)
    }
  }

  if (!isVisible) return null

  return (
    <div className="fixed top-0 left-0 right-0 z-50 p-4 bg-linear-to-r from-blue-600 to-blue-700 shadow-lg">
      <div className="max-w-7xl mx-auto">
        <Alert className="bg-white/10 border-white/20 text-white">
          <Mail className="h-4 w-4" />
          <AlertDescription className="flex items-center justify-between">
            <div className="flex-1 mr-4">
              <p className="font-medium">Verify your email address</p>
              <p className="text-sm opacity-90 mt-1">
                Please check your email and click the confirmation link to unlock all features.
                {message && (
                  <span className="block mt-2 text-sm">
                    {message.includes('sent') ? (
                      <span className="flex items-center gap-1">
                        <CheckCircle className="h-3 w-3" />
                        {message}
                      </span>
                    ) : (
                      message
                    )}
                  </span>
                )}
              </p>
            </div>
            <div className="flex items-center gap-2">
              <Button
                variant="secondary"
                size="sm"
                onClick={handleResendEmail}
                disabled={isSending}
                className="bg-white/20 hover:bg-white/30 text-white border-white/30"
              >
                {isSending ? 'Sending...' : 'Resend Email'}
              </Button>
              <button
                onClick={() => setIsVisible(false)}
                className="text-white/80 hover:text-white transition-colors"
                aria-label="Dismiss banner"
              >
                <X className="h-5 w-5" />
              </button>
            </div>
          </AlertDescription>
        </Alert>
      </div>
    </div>
  )
}