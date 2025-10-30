'use client'

import { useState } from 'react'
import { createClient } from '@/lib/supabase/client'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Loader2, CheckCircle, XCircle } from 'lucide-react'
import { publicEnv } from '@/env'

export default function TestSMSPage() {
  const [phone, setPhone] = useState('')
  const [otp, setOtp] = useState('')
  const [step, setStep] = useState<'phone' | 'verify'>('phone')
  const [loading, setLoading] = useState(false)
  const [result, setResult] = useState<{ success: boolean; message: string } | null>(null)
  
  const supabase = createClient()

  const testSendOTP = async () => {
    setLoading(true)
    setResult(null)
    
    try {
      const { error } = await supabase.auth.signInWithOtp({
        phone: phone.startsWith('+') ? phone : `+1${phone.replace(/\D/g, '')}`,
        options: {
          channel: 'sms'
        }
      })
      
      if (error) {
        setResult({ 
          success: false, 
          message: `Failed to send OTP: ${error.message}` 
        })
      } else {
        setResult({ 
          success: true, 
          message: 'OTP sent successfully! Check your phone for the verification code.' 
        })
        setStep('verify')
      }
    } catch (err) {
      setResult({ 
        success: false, 
        message: `Error: ${(err as Error).message || 'Unknown error occurred'}` 
      })
    } finally {
      setLoading(false)
    }
  }

  const testVerifyOTP = async () => {
    setLoading(true)
    setResult(null)
    
    try {
      const { data, error } = await supabase.auth.verifyOtp({
        phone: phone.startsWith('+') ? phone : `+1${phone.replace(/\D/g, '')}`,
        token: otp,
        type: 'sms'
      })
      
      if (error) {
        setResult({ 
          success: false, 
          message: `Verification failed: ${error.message}` 
        })
      } else {
        setResult({ 
          success: true, 
          message: `Success! User authenticated: ${data.user?.phone}` 
        })
        
        // Sign out after successful test
        setTimeout(() => {
          supabase.auth.signOut()
          setStep('phone')
          setPhone('')
          setOtp('')
        }, 3000)
      }
    } catch (err) {
      setResult({ 
        success: false, 
        message: `Error: ${(err as Error).message || 'Unknown error occurred'}` 
      })
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-linear-bg p-4">
      <Card className="w-full max-w-md bg-linear-card border-linear-border">
        <CardHeader>
          <CardTitle className="text-linear-text">SMS Authentication Test</CardTitle>
          <CardDescription className="text-linear-text-secondary">
            Test Twilio SMS authentication integration
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          {step === 'phone' ? (
            <>
              <div className="space-y-2">
                <label htmlFor="phone" className="text-sm font-medium text-linear-text">
                  Phone Number
                </label>
                <Input
                  id="phone"
                  type="tel"
                  placeholder="+1 (555) 123-4567"
                  value={phone}
                  onChange={(e) => setPhone(e.target.value)}
                  className="bg-linear-bg border-linear-border text-linear-text"
                />
                <p className="text-xs text-linear-text-tertiary">
                  Include country code (e.g., +1 for US)
                </p>
              </div>
              
              <Button
                onClick={testSendOTP}
                disabled={loading || !phone}
                className="w-full bg-linear-purple hover:bg-linear-purple/80 text-white"
              >
                {loading ? (
                  <>
                    <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                    Sending OTP...
                  </>
                ) : (
                  'Send OTP'
                )}
              </Button>
            </>
          ) : (
            <>
              <div className="space-y-2">
                <label htmlFor="otp" className="text-sm font-medium text-linear-text">
                  Verification Code
                </label>
                <Input
                  id="otp"
                  type="text"
                  placeholder="123456"
                  value={otp}
                  onChange={(e) => setOtp(e.target.value)}
                  className="bg-linear-bg border-linear-border text-linear-text text-center text-xl tracking-widest"
                  maxLength={6}
                />
                <p className="text-xs text-linear-text-tertiary">
                  Enter the 6-digit code sent to {phone}
                </p>
              </div>
              
              <div className="flex gap-3">
                <Button
                  variant="outline"
                  onClick={() => {
                    setStep('phone')
                    setOtp('')
                    setResult(null)
                  }}
                  className="flex-1"
                >
                  Change Number
                </Button>
                <Button
                  onClick={testVerifyOTP}
                  disabled={loading || otp.length !== 6}
                  className="flex-1 bg-linear-purple hover:bg-linear-purple/80 text-white"
                >
                  {loading ? (
                    <>
                      <Loader2 className="h-4 w-4 mr-2 animate-spin" />
                      Verifying...
                    </>
                  ) : (
                    'Verify OTP'
                  )}
                </Button>
              </div>
            </>
          )}
          
          {result && (
            <Alert className={result.success ? 'border-green-500/20 bg-green-500/5' : 'border-red-500/20 bg-red-500/5'}>
              {result.success ? (
                <CheckCircle className="h-4 w-4 text-green-500" />
              ) : (
                <XCircle className="h-4 w-4 text-red-500" />
              )}
              <AlertDescription className={result.success ? 'text-green-500' : 'text-red-500'}>
                {result.message}
              </AlertDescription>
            </Alert>
          )}
          
          <div className="pt-4 border-t border-linear-border">
            <h3 className="text-sm font-medium text-linear-text mb-2">Test Information</h3>
            <ul className="space-y-1 text-xs text-linear-text-secondary">
              <li>• Supabase URL: {publicEnv.NEXT_PUBLIC_SUPABASE_URL?.slice(0, 30)}...</li>
              <li>• SMS Provider: Twilio (configured in Supabase)</li>
              <li>• Auth Method: OTP via SMS</li>
              <li>• Session will be cleared after successful test</li>
            </ul>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}