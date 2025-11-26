'use client';

import { useState } from 'react';
import { useAuth } from '@/contexts/ClerkAuthContext';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { Label } from '@/components/ui/label';
import {
  ArrowLeft,
  Download,
  Mail,
  FileJson,
  FileSpreadsheet,
  CheckCircle2,
  AlertCircle,
} from 'lucide-react';
import Link from 'next/link';
import { MobileNavbar } from '@/components/MobileNavbar';

export default function DataExportPage() {
  const { user, session } = useAuth();
  const [exportMethod, setExportMethod] = useState('email');
  const [exportFormat, setExportFormat] = useState('json');
  const [isExporting, setIsExporting] = useState(false);
  const [exportStatus, setExportStatus] = useState<'idle' | 'success' | 'error'>('idle');
  const [statusMessage, setStatusMessage] = useState('');

  const dataExportMailto =
    'mailto:support@logyourbody.com' +
    '?subject=' +
    encodeURIComponent('LogYourBody Data Export Request') +
    '&body=' +
    encodeURIComponent(
      'Hello LogYourBody Support,\n\n' +
        'I would like to request an export of my LogYourBody account data associated with this email address.\n\n' +
        'Thank you,',
    );

  const handleExport = async () => {
    if (!user) return;

    setIsExporting(true);
    setExportStatus('idle');
    setStatusMessage('');

    try {
      const token = await session?.getToken();

      const response = await fetch(
        `${process.env.NEXT_PUBLIC_SUPABASE_URL}/functions/v1/export-user-data`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${token}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            format: exportFormat,
            emailLink: exportMethod === 'email',
          }),
        },
      );

      const data = await response.json();

      if (response.ok) {
        if (exportMethod === 'email') {
          setExportStatus('success');
          setStatusMessage(
            data.message ||
              'Export link has been sent to your email. The link will expire in 24 hours.',
          );
        } else {
          // For direct download, the response should contain the file
          const blob = new Blob([JSON.stringify(data)], {
            type: exportFormat === 'json' ? 'application/json' : 'text/csv',
          });
          const url = URL.createObjectURL(blob);
          const a = document.createElement('a');
          a.href = url;
          a.download = `logyourbody-export-${new Date().toISOString().split('T')[0]}.${exportFormat}`;
          document.body.appendChild(a);
          a.click();
          document.body.removeChild(a);
          URL.revokeObjectURL(url);

          setExportStatus('success');
          setStatusMessage('Your data has been downloaded successfully.');
        }
      } else {
        throw new Error(data.error || 'Export failed');
      }
    } catch (error) {
      console.error('Export error:', error);
      setExportStatus('error');
      setStatusMessage(
        error instanceof Error ? error.message : 'Failed to export data. Please try again.',
      );
    } finally {
      setIsExporting(false);
    }
  };

  return (
    <div className="bg-linear-bg min-h-screen pb-16 md:pb-0">
      {/* Header */}
      <header className="bg-linear-card border-linear-border sticky top-0 z-10 border-b shadow-sm">
        <div className="container mx-auto px-4 py-4">
          <div className="flex items-center gap-4">
            <Link href="/settings">
              <Button variant="ghost" size="icon">
                <ArrowLeft className="h-4 w-4" />
              </Button>
            </Link>
            <h1 className="text-linear-text text-xl font-bold">Export Your Data</h1>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="container mx-auto max-w-2xl px-4 py-6">
        <Card className="bg-linear-card border-linear-border">
          <CardHeader>
            <CardTitle>Data Export</CardTitle>
            <CardDescription>
              Download all your LogYourBody data for your records or to transfer to another service.
              Your export will include profile information, body metrics, progress history, and
              daily logs.
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
                    <Label htmlFor="email" className="cursor-pointer font-normal">
                      <div className="flex items-center gap-2">
                        <Mail className="h-4 w-4" />
                        Email Link
                      </div>
                    </Label>
                    <p className="text-linear-text-secondary text-sm">
                      Receive a secure download link via email (expires in 24 hours)
                    </p>
                  </div>
                </div>
                <div className="flex items-start space-x-3">
                  <RadioGroupItem value="download" id="download" />
                  <div className="space-y-1">
                    <Label htmlFor="download" className="cursor-pointer font-normal">
                      <div className="flex items-center gap-2">
                        <Download className="h-4 w-4" />
                        Direct Download
                      </div>
                    </Label>
                    <p className="text-linear-text-secondary text-sm">
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
                      <Label htmlFor="json" className="cursor-pointer font-normal">
                        <div className="flex items-center gap-2">
                          <FileJson className="h-4 w-4" />
                          JSON
                        </div>
                      </Label>
                      <p className="text-linear-text-secondary text-sm">
                        Complete data with all fields
                      </p>
                    </div>
                  </div>
                  <div className="flex items-start space-x-3">
                    <RadioGroupItem value="csv" id="csv" />
                    <div className="space-y-1">
                      <Label htmlFor="csv" className="cursor-pointer font-normal">
                        <div className="flex items-center gap-2">
                          <FileSpreadsheet className="h-4 w-4" />
                          CSV
                        </div>
                      </Label>
                      <p className="text-linear-text-secondary text-sm">
                        Spreadsheet-compatible format
                      </p>
                    </div>
                  </div>
                </RadioGroup>
              </div>
            )}

            {/* Status Messages */}
            {exportStatus === 'success' && (
              <div className="flex items-start gap-3 rounded-lg border border-green-500/20 bg-green-500/10 p-4">
                <CheckCircle2 className="mt-0.5 h-5 w-5 text-green-500" />
                <div>
                  <p className="text-sm text-green-900 dark:text-green-100">{statusMessage}</p>
                </div>
              </div>
            )}

            {exportStatus === 'error' && (
              <div className="flex items-start gap-3 rounded-lg border border-red-500/20 bg-red-500/10 p-4">
                <AlertCircle className="mt-0.5 h-5 w-5 text-red-500" />
                <div>
                  <p className="text-sm text-red-900 dark:text-red-100">{statusMessage}</p>
                </div>
              </div>
            )}

            {/* Export Button */}
            <Button onClick={handleExport} disabled={isExporting} className="w-full">
              {isExporting ? (
                <>
                  <div className="mr-2 h-4 w-4 animate-spin rounded-full border-b-2 border-white" />
                  Preparing export...
                </>
              ) : (
                <>
                  <Download className="mr-2 h-4 w-4" />
                  Export Data
                </>
              )}
            </Button>

            {/* Privacy Note */}
            <div className="text-linear-text-secondary space-y-2 text-center text-sm">
              <p>
                {exportMethod === 'email'
                  ? 'A secure download link will be sent to your registered email address. The link will expire after 24 hours for security.'
                  : 'Your data will be prepared and downloaded directly to this device.'}
              </p>
              <p>
                Or you can{' '}
                <a href={dataExportMailto} className="text-linear-accent underline">
                  email support to request a data export
                </a>
                .
              </p>
            </div>
          </CardContent>
        </Card>
      </main>

      {/* Mobile Navigation Bar */}
      <MobileNavbar />
    </div>
  );
}
