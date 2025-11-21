'use client'

import { useState, useCallback } from 'react'
import { Button } from '@/components/ui/button'
import { useOnboarding, type OnboardingData } from '@/contexts/OnboardingContext'
import { Upload, FileText, X, Loader2 } from 'lucide-react'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { toast } from '@/hooks/use-toast'

export function DexaUploadStep() {
  const { nextStep, updateData, previousStep } = useOnboarding()
  const [file, setFile] = useState<File | null>(null)
  const [isProcessing, setIsProcessing] = useState(false)
  const [error, setError] = useState<string | null>(null)

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
          filename: result.filename
        })
        
        // If there's only one scan, also populate the form fields
        if (data.scans.length === 1) {
          const scan = data.scans[0]
          const updates: Partial<OnboardingData> = {}
          
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
        const updates: Partial<OnboardingData> = {}
        
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
      <CardContent className="space-y-4 flex-1 overflow-y-auto">
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
          We'll extract your body composition data automatically from the PDF.
        </p>
        
        <div className="mt-4 p-3 bg-amber-50 dark:bg-amber-950/20 rounded-lg border border-amber-200 dark:border-amber-800">
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
