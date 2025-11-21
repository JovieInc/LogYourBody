'use client'

import { useState } from 'react'
import { useAuth } from '@/contexts/ClerkAuthContext'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group'
import { Label } from '@/components/ui/label'
import { ArrowLeft, Download, Mail, FileJson, FileSpreadsheet, CheckCircle2, AlertCircle } from 'lucide-react'
import Link from 'next/link'
import { MobileNavbar } from '@/components/MobileNavbar'

export default function DataExportPage() {
  const { user } = useAuth()
  const [exportMethod, setExportMethod] = useState('email')
  const [exportFormat, setExportFormat] = useState('json')
  const [isExporting, setIsExporting] = useState(false)
  const [exportStatus, setExportStatus] = useState<'idle' | 'success' | 'error'>('idle')
  const [statusMessage, setStatusMessage] = useState('')

  const handleExport = async () => {
    if (!user) return

    setIsExporting(true)
    setExportStatus('idle')
    setStatusMessage('')

    try {
      const auth = useAuth()
      const token = await auth.session?.getToken()

      const response = await fetch(`${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/export-user-data`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          format: exportFormat,
          emailLink: exportMethod === 'email'
        })
      })

      const data = await response.json()

      if (response.ok) {
        if (exportMethod === 'email') {
          setExportStatus('success')
          setStatusMessage(data.message || 'Export link has been sent to your email. The link will expire in 24 hours.')
        } else {
          // For direct download, the response should contain the file
          const blob = new Blob([JSON.stringify(data)], {
            type: exportFormat === 'json' ? 'application/json' : 'text/csv'
          })
          const url = URL.createObjectURL(blob)
          const a = document.createElement('a')
          a.href = url
          a.download = `logyourbody-export-${new Date().toISOString().split('T')[0]}.${exportFormat}`
          document.body.appendChild(a)
          a.click()
          document.body.removeChild(a)
          URL.revokeObjectURL(url)

          setExportStatus('success')
          setStatusMessage('Your data has been downloaded successfully.')
        }
      } else {
        throw new Error(data.error || 'Export failed')
      }
    } catch (error) {
      console.error('Export error:', error)
      setExportStatus('error')
      setStatusMessage(error instanceof Error ? error.message : 'Failed to export data. Please try again.')
    } finally {
      setIsExporting(false)
    }
  }

  return (
    <div className="min-h-screen bg-linear-bg pb-16 md:pb-0">
      {/* Header */}
      <header className="bg-linear-card shadow-sm border-b border-linear-border sticky top-0 z-10">
        <div className="container mx-auto px-4 py-4">
          <div className="flex items-center gap-4">
            <Link href="/settings">
              <Button variant="ghost" size="icon">
                <ArrowLeft className="h-4 w-4" />
              </Button>
            </Link>
            <h1 className="text-xl font-bold text-linear-text">Export Your Data</h1>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="container mx-auto px-4 py-6 max-w-2xl">
        <Card className="bg-linear-card border-linear-border">
          <CardHeader>
            <CardTitle>Data Export</CardTitle>
            <CardDescription>
              Download all your LogYourBody data for your records or to transfer to another service.
              Your export will include profile information, body metrics, progress history, and daily logs.
            </CardDescription>
          </CardHeader>
          <CardContent className="space-y-6">
            {/* Export Method */}
            <div className="space-y-3">
              <Label className="text-base font-semibold">Export Method</Label>
              <RadioGroup value={exportMethod} onValueChange={setExportMethod}>
                <div className="flex items-start space-x-3">
                  <RadioGroupItem value="email" id="email" />
                  <div className="space-y-1">
                    <Label htmlFor="email" className="font-normal cursor-pointer">
                      <div className="flex items-center gap-2">
                        <Mail className="h-4 w-4" />
                        Email Link
                      </div>
                    </Label>
                    <p className="text-sm text-linear-text-secondary">
                      Receive a secure download link via email (expires in 24 hours)
                    </p>
                  </div>
                </div>
                <div className="flex items-start space-x-3">
                  <RadioGroupItem value="download" id="download" />
                  <div className="space-y-1">
                    <Label htmlFor="download" className="font-normal cursor-pointer">
                      <div className="flex items-center gap-2">
                        <Download className="h-4 w-4" />
                        Direct Download
                      </div>
                    </Label>
                    <p className="text-sm text-linear-text-secondary">
                      Download directly to this device
                    </p>
                  </div>
                </div>
              </RadioGroup>
            </div>

            {/* Export Format (only for direct download) */}
            {exportMethod === 'download' && (
              <div className="space-y-3">
                <Label className="text-base font-semibold">Export Format</Label>
                <RadioGroup value={exportFormat} onValueChange={setExportFormat}>
                  <div className="flex items-start space-x-3">
                    <RadioGroupItem value="json" id="json" />
                    <div className="space-y-1">
                      <Label htmlFor="json" className="font-normal cursor-pointer">
                        <div className="flex items-center gap-2">
                          <FileJson className="h-4 w-4" />
                          JSON
                        </div>
                      </Label>
                      <p className="text-sm text-linear-text-secondary">
                        Complete data with all fields
                      </p>
                    </div>
                  </div>
                  <div className="flex items-start space-x-3">
                    <RadioGroupItem value="csv" id="csv" />
                    <div className="space-y-1">
                      <Label htmlFor="csv" className="font-normal cursor-pointer">
                        <div className="flex items-center gap-2">
                          <FileSpreadsheet className="h-4 w-4" />
                          CSV
                        </div>
                      </Label>
                      <p className="text-sm text-linear-text-secondary">
                        Spreadsheet-compatible format
                      </p>
                    </div>
                  </div>
                </RadioGroup>
              </div>
            )}

            {/* Status Messages */}
            {exportStatus === 'success' && (
              <div className="flex items-start gap-3 p-4 bg-green-500/10 border border-green-500/20 rounded-lg">
                <CheckCircle2 className="h-5 w-5 text-green-500 mt-0.5" />
                <div>
                  <p className="text-sm text-green-900 dark:text-green-100">{statusMessage}</p>
                </div>
              </div>
            )}

            {exportStatus === 'error' && (
              <div className="flex items-start gap-3 p-4 bg-red-500/10 border border-red-500/20 rounded-lg">
                <AlertCircle className="h-5 w-5 text-red-500 mt-0.5" />
                <div>
                  <p className="text-sm text-red-900 dark:text-red-100">{statusMessage}</p>
                </div>
              </div>
            )}

            {/* Export Button */}
            <Button
              onClick={handleExport}
              disabled={isExporting}
              className="w-full"
            >
              {isExporting ? (
                <>
                  <div className="animate-spin rounded-full h-4 w-4 border-b-2 border-white mr-2" />
                  Preparing export...
                </>
              ) : (
                <>
                  <Download className="h-4 w-4 mr-2" />
                  Export Data
                </>
              )}
            </Button>

            {/* Privacy Note */}
            <p className="text-sm text-linear-text-secondary text-center">
              {exportMethod === 'email'
                ? "A secure download link will be sent to your registered email address. The link will expire after 24 hours for security."
                : "Your data will be prepared and downloaded directly to this device."
              }
            </p>
          </CardContent>
        </Card>
      </main>

      {/* Mobile Navigation Bar */}
      <MobileNavbar />
    </div>
  )
}