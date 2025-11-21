'use client'

import { useState } from 'react'
import { useAuth } from '@/contexts/ClerkAuthContext'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { uploadToStorage, ensurePublicUrl } from '@/utils/storage-utils'
import { createClient } from '@/lib/supabase/client'
import { Upload, Image as ImageIcon, CheckCircle, XCircle } from 'lucide-react'

interface UploadResult {
  uploadedUrl: string
  correctedUrl: string
  retrievedUrl: string
  metricsId: string
  fileName: string
}

export default function TestPhotoUploadPage() {
  const { user } = useAuth()
  const [file, setFile] = useState<File | null>(null)
  const [preview, setPreview] = useState<string | null>(null)
  const [uploadResult, setUploadResult] = useState<UploadResult | null>(null)
  const [isUploading, setIsUploading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  const handleFileSelect = (e: React.ChangeEvent<HTMLInputElement>) => {
    const selectedFile = e.target.files?.[0]
    if (!selectedFile) return

    setFile(selectedFile)
    setError(null)
    setUploadResult(null)

    // Create preview
    const reader = new FileReader()
    reader.onload = (e) => {
      setPreview(e.target?.result as string)
    }
    reader.readAsDataURL(selectedFile)
  }

  const testUpload = async () => {
    if (!file || !user) return

    setIsUploading(true)
    setError(null)
    setUploadResult(null)

    try {
      const supabase = createClient()
      const fileName = `${user.id}/test-${Date.now()}.jpg`

      console.log('Starting upload...')
      console.log('File:', file.name, file.size, file.type)
      console.log('Path:', fileName)

      // Test upload
      const { publicUrl, error: uploadError } = await uploadToStorage(
        'photos',
        fileName,
        file,
        { contentType: file.type }
      )

      if (uploadError) throw uploadError

      console.log('Upload successful!')
      console.log('Public URL:', publicUrl)

      // Test creating body metrics entry
      const { data: metricsData, error: metricsError } = await supabase
        .from('body_metrics')
        .insert({
          user_id: user.id,
          date: new Date().toISOString().split('T')[0],
          photo_url: publicUrl,
          notes: 'Test photo upload'
        })
        .select()
        .single()

      if (metricsError) throw metricsError

      console.log('Metrics entry created:', metricsData)

      // Test retrieving the photo
      const { data: retrievedData, error: retrieveError } = await supabase
        .from('body_metrics')
        .select('photo_url')
        .eq('id', metricsData.id)
        .single()

      if (retrieveError) throw retrieveError

      console.log('Retrieved photo URL:', retrievedData.photo_url)

      setUploadResult({
        uploadedUrl: publicUrl,
        correctedUrl: ensurePublicUrl(publicUrl),
        retrievedUrl: retrievedData.photo_url,
        metricsId: metricsData.id,
        fileName: fileName
      })

    } catch (err) {
      console.error('Upload test failed:', err)
      setError(err instanceof Error ? err.message : 'Upload failed')
    } finally {
      setIsUploading(false)
    }
  }

  if (!user) {
    return (
      <div className="container mx-auto py-8">
        <Alert>
          <AlertDescription>Please log in to test photo upload.</AlertDescription>
        </Alert>
      </div>
    )
  }

  return (
    <div className="container mx-auto py-8 max-w-2xl">
      <Card>
        <CardHeader>
          <CardTitle>Photo Upload Test</CardTitle>
        </CardHeader>
        <CardContent className="space-y-6">
          {/* File Input */}
          <div>
            <input
              type="file"
              id="photo-input"
              accept="image/*"
              onChange={handleFileSelect}
              className="hidden"
            />
            <label htmlFor="photo-input">
              <Button variant="outline" asChild>
                <span>
                  <ImageIcon className="h-4 w-4 mr-2" />
                  Select Photo
                </span>
              </Button>
            </label>
            {file && (
              <p className="mt-2 text-sm text-muted-foreground">
                Selected: {file.name} ({(file.size / 1024 / 1024).toFixed(2)} MB)
              </p>
            )}
          </div>

          {/* Preview */}
          {preview && (
            <div className="relative w-full max-w-sm">
              <img 
                src={preview} 
                alt="Preview" 
                className="w-full rounded-lg border"
              />
            </div>
          )}

          {/* Upload Button */}
          {file && (
            <Button 
              onClick={testUpload} 
              disabled={isUploading}
              className="w-full"
            >
              {isUploading ? (
                <>
                  <Upload className="h-4 w-4 mr-2 animate-spin" />
                  Uploading...
                </>
              ) : (
                <>
                  <Upload className="h-4 w-4 mr-2" />
                  Test Upload
                </>
              )}
            </Button>
          )}

          {/* Error Display */}
          {error && (
            <Alert variant="destructive">
              <XCircle className="h-4 w-4" />
              <AlertDescription>{error}</AlertDescription>
            </Alert>
          )}

          {/* Success Result */}
          {uploadResult && (
            <Alert className="border-green-200 bg-green-50 text-green-900">
              <CheckCircle className="h-4 w-4 text-green-600" />
              <AlertDescription>
                <div className="space-y-2">
                  <p className="font-semibold">Upload successful!</p>
                  <div className="text-xs space-y-1 font-mono">
                    <p>File: {uploadResult.fileName}</p>
                    <p>Metrics ID: {uploadResult.metricsId}</p>
                    <p className="break-all">Uploaded URL: {uploadResult.uploadedUrl}</p>
                    <p className="break-all">Corrected URL: {uploadResult.correctedUrl}</p>
                    <p className="break-all">Retrieved URL: {uploadResult.retrievedUrl}</p>
                  </div>
                  {uploadResult.correctedUrl && (
                    <div className="mt-4">
                      <p className="text-sm mb-2">Uploaded Image:</p>
                      <img 
                        src={uploadResult.correctedUrl} 
                        alt="Uploaded" 
                        className="w-full max-w-sm rounded-lg border"
                        onError={(e) => {
                          console.error('Image load error:', e)
                          setError('Failed to load uploaded image')
                        }}
                      />
                    </div>
                  )}
                </div>
              </AlertDescription>
            </Alert>
          )}
        </CardContent>
      </Card>
    </div>
  )
}
