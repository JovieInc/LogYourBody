'use client'

import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { toast } from '@/hooks/use-toast'
import { FileText, Upload, CheckCircle, XCircle } from 'lucide-react'

type PdfParseResult =
  | { success: true; data: unknown; filename: string }
  | { success: false; error: string; errorDetails?: unknown }

export default function TestPDFPage() {
  const [isProcessing, setIsProcessing] = useState(false)
  const [result, setResult] = useState<PdfParseResult | null>(null)
  const [selectedFile, setSelectedFile] = useState<File | null>(null)

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (file && file.type === 'application/pdf') {
      setSelectedFile(file)
      setResult(null)
    } else {
      toast({
        title: "Invalid file",
        description: "Please select a PDF file",
        variant: "destructive"
      })
    }
  }

  const testPDFParsing = async () => {
    if (!selectedFile) {
      toast({
        title: "No file selected",
        description: "Please select a PDF file first",
        variant: "destructive"
      })
      return
    }

    setIsProcessing(true)
    setResult(null)

    try {
      const formData = new FormData()
      formData.append('file', selectedFile)

      console.log('Sending PDF to API...')
      const response = await fetch('/api/parse-pdf', {
        method: 'POST',
        body: formData
      })

      const data = await response.json()
      console.log('API Response:', data)

      if (!response.ok) {
        throw new Error(data.error || 'Failed to parse PDF')
      }

      setResult({
        success: true,
        data: data.data,
        filename: data.filename
      })

      toast({
        title: "PDF parsed successfully!",
        description: "Check the results below",
      })

    } catch (error) {
      console.error('PDF parsing error:', error)
      setResult({
        success: false,
        error: error instanceof Error ? error.message : 'Unknown error',
        errorDetails: error
      })

      toast({
        title: "Parsing failed",
        description: error instanceof Error ? error.message : "Failed to parse PDF",
        variant: "destructive"
      })
    } finally {
      setIsProcessing(false)
    }
  }

  return (
    <div className="min-h-screen bg-linear-bg p-8">
      <div className="max-w-2xl mx-auto">
        <Card className="bg-linear-card border-linear-border">
          <CardHeader>
            <CardTitle className="text-linear-text">PDF Parsing Test</CardTitle>
            <CardDescription className="text-linear-text-secondary">
              Test OpenAI PDF parsing functionality
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-6">
            <div className="space-y-4">
              <div>
                <input
                  type="file"
                  accept="application/pdf"
                  onChange={handleFileChange}
                  className="block w-full text-sm text-linear-text
                    file:mr-4 file:py-2 file:px-4
                    file:rounded-full file:border-0
                    file:text-sm file:font-semibold
                    file:bg-linear-purple file:text-white
                    hover:file:bg-linear-purple/80"
                />
              </div>

              {selectedFile && (
                <div className="p-3 bg-linear-bg rounded-lg">
                  <p className="text-sm text-linear-text">
                    Selected: {selectedFile.name}
                  </p>
                  <p className="text-xs text-linear-text-secondary">
                    Size: {(selectedFile.size / 1024 / 1024).toFixed(2)} MB
                  </p>
                </div>
              )}

              <Button 
                onClick={testPDFParsing}
                disabled={isProcessing || !selectedFile}
                className="w-full bg-linear-purple hover:bg-linear-purple/80"
              >
                {isProcessing ? (
                  <>
                    <Upload className="h-4 w-4 mr-2 animate-spin" />
                    Processing PDF...
                  </>
                ) : (
                  <>
                    <FileText className="h-4 w-4 mr-2" />
                    Parse PDF with OpenAI
                  </>
                )}
              </Button>
            </div>

            {result && (
              <div className={`p-4 rounded-lg border ${
                result.success 
                  ? 'bg-green-900/20 border-green-800' 
                  : 'bg-red-900/20 border-red-800'
              }`}>
                <div className="flex items-start gap-3">
                  {result.success ? (
                    <CheckCircle className="h-5 w-5 text-green-500 mt-0.5" />
                  ) : (
                    <XCircle className="h-5 w-5 text-red-500 mt-0.5" />
                  )}
                  <div className="flex-1 space-y-2">
                    <p className="font-medium text-linear-text">
                      {result.success ? 'Parsing Successful' : 'Parsing Failed'}
                    </p>
                    
                    {result.success ? (
                      <>
                        <p className="text-sm text-linear-text-secondary">
                          File: {result.filename}
                        </p>
                        <pre className="text-xs text-linear-text-secondary mt-2 p-2 bg-linear-bg rounded overflow-auto max-h-96">
                          {JSON.stringify(result.data, null, 2)}
                        </pre>
                      </>
                    ) : (
                      <>
                        <p className="text-sm text-red-400">
                          Error: {result.error}
                        </p>
                        <pre className="text-xs text-linear-text-secondary mt-2 p-2 bg-linear-bg rounded overflow-auto">
                          {JSON.stringify(result.errorDetails, null, 2)}
                        </pre>
                      </>
                    )}
                  </div>
                </div>
              </div>
            )}

            <div className="p-4 bg-linear-bg rounded-lg">
              <h3 className="text-sm font-medium text-linear-text mb-2">Test PDFs to try:</h3>
              <ul className="text-xs text-linear-text-secondary space-y-1">
                <li>• DEXA scan reports</li>
                <li>• InBody analysis reports</li>
                <li>• Body composition reports</li>
                <li>• Any PDF with weight/body fat data</li>
              </ul>
            </div>
          </CardContent>
        </Card>
      </div>
    </div>
  )
}
