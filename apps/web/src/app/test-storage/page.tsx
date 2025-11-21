'use client'

import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { uploadToStorage } from '@/utils/storage-utils'
import { createClient } from '@/lib/supabase/client'
import { useAuth } from '@/contexts/ClerkAuthContext'
import { toast } from '@/hooks/use-toast'
import { Upload, CheckCircle, XCircle } from 'lucide-react'

interface BucketInfo {
  id: string
  public?: boolean
}

interface BucketTestResult {
  success: boolean
  buckets?: BucketInfo[]
  photosBucketExists?: boolean
  photosBucketDetails?: BucketInfo
  error?: unknown
}

type UploadTestResult =
  | {
    success: true
    publicUrl: string
    fileName: string
    bucketTest: BucketTestResult
  }
  | {
    success: false
    error: string
    errorDetails: unknown
    bucketTest?: BucketTestResult
  }

export default function TestStoragePage() {
  const { user } = useAuth()
  const [isUploading, setIsUploading] = useState(false)
  const [uploadResult, setUploadResult] = useState<UploadTestResult | null>(null)

  const testBucketCreation = async (): Promise<BucketTestResult> => {
    try {
      const supabase = createClient()
      const { data, error } = await supabase.storage.listBuckets()

      if (error) {
        console.error('Error listing buckets:', error)
        return { success: false, error }
      }

      console.log('Available buckets:', data)
      const photosBucket = data.find(b => b.id === 'photos')

      return {
        success: true,
        buckets: data,
        photosBucketExists: !!photosBucket,
        photosBucketDetails: photosBucket ?? undefined
      }
    } catch (error) {
      console.error('Bucket test error:', error)
      return { success: false, error }
    }
  }

  const testPhotoUpload = async () => {
    if (!user) {
      toast({
        title: "Not authenticated",
        description: "Please log in to test photo upload",
        variant: "destructive"
      })
      return
    }

    setIsUploading(true)
    setUploadResult(null)

    try {
      // First check bucket status
      const bucketTest = await testBucketCreation()
      console.log('Bucket test result:', bucketTest)

      // Create a test image blob
      const canvas = document.createElement('canvas')
      canvas.width = 200
      canvas.height = 200
      const ctx = canvas.getContext('2d')
      if (!ctx) throw new Error('Could not create canvas context')

      // Draw a test pattern
      ctx.fillStyle = '#4B5563'
      ctx.fillRect(0, 0, 200, 200)
      ctx.fillStyle = '#9333EA'
      ctx.fillRect(50, 50, 100, 100)
      ctx.fillStyle = '#FFFFFF'
      ctx.font = '20px Arial'
      ctx.fillText('TEST', 70, 110)

      // Convert to blob
      const blob = await new Promise<Blob>((resolve) => {
        canvas.toBlob((b) => resolve(b!), 'image/jpeg', 0.9)
      })

      // Test upload
      const fileName = `${user.id}/test-${Date.now()}.jpg`
      const { publicUrl, error } = await uploadToStorage(
        'photos',
        fileName,
        blob,
        { contentType: 'image/jpeg' }
      )

      if (error) {
        throw error
      }

      setUploadResult({
        success: true,
        publicUrl,
        fileName,
        bucketTest
      })

      toast({
        title: "Upload successful!",
        description: "Test photo uploaded successfully",
      })

      // Test if URL is accessible
      const response = await fetch(publicUrl)
      console.log('URL accessibility test:', {
        url: publicUrl,
        status: response.status,
        ok: response.ok
      })

    } catch (error) {
      console.error('Upload test error:', error)
      setUploadResult({
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error',
        errorDetails: error
      })

      toast({
        title: "Upload failed",
        description: error instanceof Error ? error.message : "Test upload failed",
        variant: "destructive"
      })
    } finally {
      setIsUploading(false)
    }
  }

  return (
    <div className="min-h-screen bg-linear-bg p-8">
      <div className="max-w-2xl mx-auto">
        <Card className="bg-linear-card border-linear-border">
          <CardHeader>
            <CardTitle className="text-linear-text">Storage Test Page</CardTitle>
            <CardDescription className="text-linear-text-secondary">
              Test Supabase storage functionality for photo uploads
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-6">
            <div className="space-y-4">
              <Button
                onClick={testPhotoUpload}
                disabled={isUploading || !user}
                className="w-full bg-linear-purple hover:bg-linear-purple/80"
              >
                {isUploading ? (
                  <>
                    <Upload className="h-4 w-4 mr-2 animate-spin" />
                    Testing upload...
                  </>
                ) : (
                  <>
                    <Upload className="h-4 w-4 mr-2" />
                    Test Photo Upload
                  </>
                )}
              </Button>

              {!user && (
                <p className="text-sm text-linear-text-secondary text-center">
                  Please log in to test photo uploads
                </p>
              )}
            </div>

            {uploadResult && (
              <div className={`p-4 rounded-lg border ${uploadResult.success
                  ? 'bg-green-900/20 border-green-800'
                  : 'bg-red-900/20 border-red-800'
                }`}>
                <div className="flex items-start gap-3">
                  {uploadResult.success ? (
                    <CheckCircle className="h-5 w-5 text-green-500 mt-0.5" />
                  ) : (
                    <XCircle className="h-5 w-5 text-red-500 mt-0.5" />
                  )}
                  <div className="flex-1 space-y-2">
                    <p className="font-medium text-linear-text">
                      {uploadResult.success ? 'Upload Successful' : 'Upload Failed'}
                    </p>

                    {uploadResult.success ? (
                      <>
                        <p className="text-sm text-linear-text-secondary">
                          File: {uploadResult.fileName}
                        </p>
                        <p className="text-sm text-linear-text-secondary break-all">
                          URL: {uploadResult.publicUrl}
                        </p>
                        {uploadResult.bucketTest && (
                          <div className="mt-2 p-2 bg-linear-bg rounded">
                            <p className="text-xs text-linear-text-secondary">
                              Photos bucket exists: {uploadResult.bucketTest.photosBucketExists ? 'Yes' : 'No'}
                            </p>
                            {uploadResult.bucketTest.photosBucketDetails && (
                              <p className="text-xs text-linear-text-secondary">
                                Bucket public: {uploadResult.bucketTest.photosBucketDetails.public ? 'Yes' : 'No'}
                              </p>
                            )}
                          </div>
                        )}
                      </>
                    ) : (
                      <>
                        <p className="text-sm text-red-400">
                          Error: {uploadResult.error}
                        </p>
                        <pre className="text-xs text-linear-text-secondary mt-2 p-2 bg-linear-bg rounded overflow-auto">
                          {JSON.stringify(uploadResult.errorDetails, null, 2)}
                        </pre>
                      </>
                    )}
                  </div>
                </div>
              </div>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
