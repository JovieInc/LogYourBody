'use client'

import { useState, useCallback, FormEvent } from 'react'
import { Button } from '@/components/ui/button'
import { useOnboarding } from '@/contexts/OnboardingContext'
import { Upload, FileText, X, Loader2, Link2, CheckCircle } from 'lucide-react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { toast } from '@/hooks/use-toast'

type BodyspecSession = {
  accessToken: string
  client: string
  uid: string
  expiry?: string
  tokenType?: string
}

type NormalizedScan = {
  date: string
  weight: number | null
  weight_unit: 'lbs' | 'kg'
  body_fat_percentage?: number | null
  lean_mass?: number | null
  bone_mass?: number | null
}

type OnboardingUpdates = {
  weight?: number
  bodyFatPercentage?: number
  leanMass?: number
  fatMass?: number
  boneMass?: number
  scanDate?: string
  dataSource?: 'pdf' | 'bodyspec' | 'manual'
}

export function DexaUploadStep() {
  const { nextStep, updateData, previousStep } = useOnboarding()
  const [file, setFile] = useState<File | null>(null)
  const [isProcessing, setIsProcessing] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [bodyspecDialogOpen, setBodyspecDialogOpen] = useState(false)
  const [bodyspecEmail, setBodyspecEmail] = useState('')
  const [bodyspecPassword, setBodyspecPassword] = useState('')
  const [bodyspecError, setBodyspecError] = useState<string | null>(null)
  const [isConnecting, setIsConnecting] = useState(false)
  const [bodyspecSession, setBodyspecSession] = useState<BodyspecSession | null>(null)
  const canSubmitBodyspec = bodyspecEmail.trim().length > 0 && (bodyspecPassword.trim().length > 0 || bodyspecSession !== null)

  const handleFileSelect = useCallback((e: React.ChangeEvent<HTMLInputElement>) => {
    const selectedFile = e.target.files?.[0]
    
    if (selectedFile) {
      if (selectedFile.type !== 'application/pdf') {
        setError('Please select a PDF file')
        return
      }
      
      if (selectedFile.size > 10 * 1024 * 1024) { // 10MB limit
        setError('File size must be less than 10MB')
        return
      }
      
      setFile(selectedFile)
      setError(null)
    }
  }, [])

  const handleDrop = useCallback((e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault()
    e.stopPropagation()
    
    const droppedFile = e.dataTransfer.files[0]
    
    if (droppedFile) {
      if (droppedFile.type !== 'application/pdf') {
        setError('Please select a PDF file')
        return
      }
      
      if (droppedFile.size > 10 * 1024 * 1024) {
        setError('File size must be less than 10MB')
        return
      }
      
      setFile(droppedFile)
      setError(null)
    }
  }, [])

  const handleDragOver = (e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault()
    e.stopPropagation()
  }

  const removeFile = () => {
    setFile(null)
    setError(null)
  }

  const handleBodyspecDialogChange = (open: boolean) => {
    setBodyspecDialogOpen(open)
    if (!open) {
      setBodyspecPassword('')
      setBodyspecError(null)
      setIsConnecting(false)
    }
  }

  const connectBodyspec = async (event: FormEvent<HTMLFormElement>) => {
    event.preventDefault()

    const trimmedEmail = bodyspecEmail.trim()

    if (!trimmedEmail || (!bodyspecPassword && !bodyspecSession)) {
      setBodyspecError('Enter your BodySpec email and password to continue.')
      return
    }

    setIsConnecting(true)
    setBodyspecError(null)

    try {
      const response = await fetch('/api/import/bodyspec', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          email: trimmedEmail,
          password: bodyspecPassword,
          session: bodyspecSession ?? undefined
        })
      })

      const result = await response.json()

      if (!response.ok) {
        throw new Error(result?.error || 'Failed to connect to BodySpec')
      }

      const scans = Array.isArray(result?.scans) ? (result.scans as NormalizedScan[]) : []

      if (scans.length === 0) {
        setBodyspecError('We couldn’t find any BodySpec scans for this account yet.')
        return
      }

      if (result?.session) {
        setBodyspecSession(result.session as BodyspecSession)
      }

      updateData({
        extractedScans: scans,
        scanCount: scans.length,
        filename: 'BodySpec Sync',
        dataSource: 'bodyspec'
      })

      if (scans.length === 1) {
        const scan = scans[0]
        const updates: OnboardingUpdates = {
          dataSource: 'bodyspec'
        }

        if (typeof scan.weight === 'number' && !Number.isNaN(scan.weight)) {
          updates.weight = scan.weight_unit === 'lbs' ? scan.weight * 0.453592 : scan.weight
        }
        if (typeof scan.body_fat_percentage === 'number') {
          updates.bodyFatPercentage = scan.body_fat_percentage
        }
        if (typeof scan.lean_mass === 'number') {
          updates.leanMass = scan.lean_mass
        }
        if (typeof scan.bone_mass === 'number') {
          updates.boneMass = scan.bone_mass
        }
        if (scan.date) {
          updates.scanDate = scan.date
        }

        if (updates.weight && updates.bodyFatPercentage) {
          updates.fatMass = updates.weight * (updates.bodyFatPercentage / 100)
        }

        updateData(updates)
      }

      toast({
        title: 'BodySpec connected',
        description: scans.length === 1
          ? 'We pulled your latest DEXA scan.'
          : `Imported ${scans.length} BodySpec scans.`,
      })

      setBodyspecDialogOpen(false)
      setBodyspecPassword('')
      setError(null)
      nextStep()
    } catch (err) {
      console.error('BodySpec connection error:', err)
      const message = err instanceof Error ? err.message : 'Failed to connect to BodySpec.'
      setBodyspecError(message)
    } finally {
      setIsConnecting(false)
    }
  }

  const processFile = async () => {
    if (!file) return

    setIsProcessing(true)
    setError(null)
    
    try {
      const formData = new FormData()
      formData.append('file', file)
      
      // Try the new PDF parser first
      let response = await fetch('/api/parse-pdf-v2', {
        method: 'POST',
        body: formData,
      })
      
      // If v2 fails, fallback to original
      if (!response.ok) {
        console.log('PDF v2 failed, trying original parser...')
        response = await fetch('/api/parse-pdf', {
          method: 'POST',
          body: formData,
        })
      }
      
      const result = await response.json()
      
      if (!response.ok) {
        throw new Error(result.error || 'Failed to process PDF')
      }
      
      // Check if we got successful data
      if (!result.success || !result.data) {
        throw new Error('No data extracted from PDF')
      }
      
      const data = result.data
      
      // Check if we have multiple scans
      if (data.scans && Array.isArray(data.scans) && data.scans.length > 0) {
        // Store all scans in the context
        updateData({
          extractedScans: data.scans,
          scanCount: data.scans.length,
          filename: result.filename,
          dataSource: 'pdf'
        })
        
        // If there's only one scan, also populate the form fields
        if (data.scans.length === 1) {
          const scan = data.scans[0]
          const updates: OnboardingUpdates = {
            dataSource: 'pdf'
          }
          
          if (scan.weight) {
            updates.weight = scan.weight_unit === 'lbs' ? scan.weight * 0.453592 : scan.weight
          }
          if (scan.body_fat_percentage) {
            updates.bodyFatPercentage = scan.body_fat_percentage
          }
          if (scan.muscle_mass) {
            updates.leanMass = scan.muscle_mass
          }
          if (scan.date) {
            updates.scanDate = scan.date
          }
          if (scan.bone_mass) {
            updates.boneMass = scan.bone_mass
          }
          
          // Calculate fat mass if we have weight and body fat percentage
          if (updates.weight && updates.bodyFatPercentage) {
            updates.fatMass = updates.weight * (updates.bodyFatPercentage / 100)
          }
          
          updateData(updates)
        }
      } else {
        // Fallback to old format if no scans array
        const updates: OnboardingUpdates = {
          dataSource: 'pdf'
        }
        
        if (data.weight) {
          updates.weight = data.weight_unit === 'lbs' ? data.weight * 0.453592 : data.weight
        }
        if (data.body_fat_percentage) {
          updates.bodyFatPercentage = data.body_fat_percentage
        }
        if (data.muscle_mass) {
          updates.leanMass = data.muscle_mass
        }
        if (data.date) {
          updates.scanDate = data.date
        }
        
        if (updates.weight && updates.bodyFatPercentage) {
          updates.fatMass = updates.weight * (updates.bodyFatPercentage / 100)
        }
        
        updateData(updates)
      }
      
      toast({
        title: 'PDF processed successfully',
        description: data.scans && data.scans.length > 0 
          ? `Found ${data.scans.length} scan${data.scans.length > 1 ? 's' : ''} in your PDF`
          : 'We extracted your body composition data.',
      })
      
      nextStep()
    } catch (err) {
      console.error('Error processing PDF:', err)
      
      let errorMessage = 'Failed to process PDF. Please try again or skip this step.'
      
      if (err instanceof Error) {
        if (err.message.includes('OpenAI')) {
          errorMessage = 'AI service is temporarily unavailable. Please try again later or skip this step.'
        } else if (err.message.includes('No data extracted')) {
          errorMessage = 'Could not extract body composition data from this PDF. Please ensure it\'s a DEXA or body composition scan.'
        } else if (err.message.includes('text from PDF')) {
          errorMessage = 'This PDF appears to be image-based. Please try a text-based PDF or skip this step.'
        } else {
          errorMessage = err.message
        }
      }
      
      setError(errorMessage)
      
      toast({
        title: 'Error processing PDF',
        description: errorMessage,
        variant: 'destructive'
      })
    } finally {
      setIsProcessing(false)
    }
  }

  const skipStep = () => {
    // User can manually enter data later
    nextStep()
  }

  return (
    <Card className="bg-linear-card border-linear-border max-h-[85vh] flex flex-col">
      <CardHeader className="flex-shrink-0">
        <CardTitle className="text-linear-text">Upload your DEXA scan</CardTitle>
        <CardDescription className="text-linear-text-secondary">
          Support for BodySpec, DexaFit, and other providers
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-6 flex-1 overflow-y-auto">
        {!file ? (
          <div
            onDrop={handleDrop}
            onDragOver={handleDragOver}
            className="border-2 border-dashed border-linear-border rounded-lg p-8 text-center cursor-pointer hover:border-linear-purple/50 transition-colors"
          >
            <input
              type="file"
              accept=".pdf"
              onChange={handleFileSelect}
              className="hidden"
              id="pdf-upload"
            />
            <label htmlFor="pdf-upload" className="cursor-pointer">
              <Upload className="h-12 w-12 text-linear-text-tertiary mx-auto mb-4" />
              <p className="text-linear-text mb-2">
                Drag and drop your DEXA scan PDF here
              </p>
              <p className="text-sm text-linear-text-secondary">
                or click to browse
              </p>
            </label>
          </div>
        ) : (
          <div className="bg-linear-bg rounded-lg p-4 flex items-center justify-between">
            <div className="flex items-center gap-3">
              <FileText className="h-8 w-8 text-linear-purple" />
              <div>
                <p className="text-linear-text font-medium">{file.name}</p>
                <p className="text-sm text-linear-text-secondary">
                  {(file.size / 1024 / 1024).toFixed(2)} MB
                </p>
              </div>
            </div>
            <Button
              variant="ghost"
              size="icon"
              onClick={removeFile}
              disabled={isProcessing}
            >
              <X className="h-4 w-4" />
            </Button>
          </div>
        )}

        {error && (
          <Alert variant="destructive">
            <AlertDescription>{error}</AlertDescription>
          </Alert>
        )}

        <p className="text-sm text-linear-text-secondary">
          We'll extract your body composition data automatically from a PDF, or connect directly to BodySpec for an instant sync.
        </p>

        <Dialog open={bodyspecDialogOpen} onOpenChange={handleBodyspecDialogChange}>
          <div className="rounded-lg border border-linear-border/70 bg-linear-bg/60 p-5 shadow-sm">
            <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
              <div className="space-y-1 text-left">
                <p className="text-linear-text font-semibold">Connect to BodySpec</p>
                <p className="text-sm text-linear-text-secondary">
                  Import your full DEXA history securely in seconds.
                </p>
              </div>
              <DialogTrigger asChild>
                <Button
                  type="button"
                  variant="outline"
                  className="bg-linear-purple/10 border-linear-purple/30 text-linear-purple hover:bg-linear-purple/20"
                >
                  <Link2 className="mr-2 h-4 w-4" />
                  Connect to BodySpec
                </Button>
              </DialogTrigger>
            </div>
            <p className="mt-3 text-xs text-linear-text-tertiary">
              Your credentials are encrypted in transit and never stored.
            </p>
            {bodyspecSession && (
              <div className="mt-3 flex items-center gap-2 text-xs text-emerald-500">
                <CheckCircle className="h-3.5 w-3.5" />
                <span>Connected. Your recent scans are ready to review.</span>
              </div>
            )}
          </div>

          <DialogContent className="bg-linear-card border-linear-border text-linear-text">
            <DialogHeader>
              <DialogTitle>Connect to BodySpec</DialogTitle>
              <DialogDescription className="text-linear-text-secondary">
                Sign in with your BodySpec credentials so we can import your DEXA scans automatically.
              </DialogDescription>
            </DialogHeader>
            <form onSubmit={connectBodyspec} className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="bodyspec-email" className="text-linear-text">BodySpec email</Label>
                <Input
                  id="bodyspec-email"
                  type="email"
                  autoComplete="email"
                  value={bodyspecEmail}
                  onChange={(e) => setBodyspecEmail(e.target.value)}
                  className="bg-linear-bg border-linear-border text-linear-text"
                  placeholder="you@example.com"
                  required
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="bodyspec-password" className="text-linear-text">Password</Label>
                <Input
                  id="bodyspec-password"
                  type="password"
                  autoComplete="current-password"
                  value={bodyspecPassword}
                  onChange={(e) => setBodyspecPassword(e.target.value)}
                  className="bg-linear-bg border-linear-border text-linear-text"
                  placeholder="Enter your password"
                  required={!bodyspecSession}
                />
                <p className="text-xs text-linear-text-tertiary">
                  We only use your password to fetch your scans and never store it.
                </p>
              </div>
              {bodyspecError && (
                <Alert variant="destructive">
                  <AlertDescription>{bodyspecError}</AlertDescription>
                </Alert>
              )}
              <DialogFooter>
                <Button
                  type="button"
                  variant="ghost"
                  onClick={() => handleBodyspecDialogChange(false)}
                  disabled={isConnecting}
                >
                  Cancel
                </Button>
                <Button
                  type="submit"
                  className="bg-linear-purple hover:bg-linear-purple/90 text-white"
                  disabled={!canSubmitBodyspec || isConnecting}
                >
                  {isConnecting ? (
                    <>
                      <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                      Connecting…
                    </>
                  ) : (
                    'Import from BodySpec'
                  )}
                </Button>
              </DialogFooter>
            </form>
          </DialogContent>
        </Dialog>

        <div className="p-3 bg-amber-50 dark:bg-amber-950/20 rounded-lg border border-amber-200 dark:border-amber-800">
          <p className="text-sm text-amber-800 dark:text-amber-300">
            <strong>Tip:</strong> If PDF upload fails, try taking a screenshot of your scan results and uploading it as an image instead.
          </p>
        </div>

      </CardContent>
      {/* Fixed button footer */}
      <div className="p-6 pt-0 flex-shrink-0">
        <div className="flex gap-3">
          <Button
            variant="ghost"
            onClick={previousStep}
            disabled={isProcessing}
          >
            Back
          </Button>
          
          <Button
            variant="outline"
            onClick={skipStep}
            disabled={isProcessing}
            className="ml-auto"
          >
            Skip for now
          </Button>
          
          <Button
            onClick={processFile}
            disabled={!file || isProcessing}
            className="bg-linear-purple hover:bg-linear-purple/90 text-white"
          >
            {isProcessing ? (
              <>
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                Processing...
              </>
            ) : (
              'Upload PDF'
            )}
          </Button>
        </div>
      </div>
    </Card>
  )
}