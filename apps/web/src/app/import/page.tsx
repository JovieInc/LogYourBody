'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/contexts/ClerkAuthContext';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
// import { Alert, AlertDescription } from '@/components/ui/alert' // Not used
// import { Separator } from '@/components/ui/separator' // Not used
// import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs' // Not used
import { toast } from '@/hooks/use-toast';
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog';
import { Progress } from '@/components/ui/progress';
import {
  ArrowLeft,
  Upload,
  FileSpreadsheet,
  FileText,
  Image as ImageIcon,
  CheckCircle,
  Check,
  X as XIcon,
  Loader2,
  AlertCircle,
} from 'lucide-react';
import Link from 'next/link';
import { format } from 'date-fns';
import { createClient } from '@/lib/supabase/client';
import { uploadToStorage } from '@/utils/storage-utils';

type FileType = 'image' | 'pdf' | 'csv' | 'unknown';

type WeightUnit = 'kg' | 'lbs';

interface ParsedData {
  type: 'weight' | 'body_composition' | 'photos';
  entries: Array<{
    date: string;
    weight?: number;
    weight_unit?: WeightUnit;
    body_fat_percentage?: number;
    muscle_mass?: number;
    waist?: number;
    hip?: number;
    notes?: string;
    photo_url?: string;
    angle?: string;
  }>;
  metadata?: {
    source?: string;
    total_entries?: number;
    date_range?: {
      start: string;
      end: string;
    };
  };
}

export default function ImportPage() {
  const { user, loading } = useAuth();
  const router = useRouter();
  const [uploadedFiles, setUploadedFiles] = useState<File[]>([]);
  const [isProcessing, setIsProcessing] = useState(false);
  const [parsedData, setParsedData] = useState<ParsedData | null>(null);
  const [selectedEntries, setSelectedEntries] = useState<Set<number>>(new Set());
  const [processingStatus, setProcessingStatus] = useState<string>('');
  const [uploadProgress, setUploadProgress] = useState(0);
  const [uploadErrors, setUploadErrors] = useState<string[]>([]);
  const [successCount, setSuccessCount] = useState(0);

  if (loading) {
    return (
      <div className="bg-linear-bg flex min-h-screen items-center justify-center">
        <div className="border-linear-purple h-8 w-8 animate-spin rounded-full border-2 border-t-transparent" />
      </div>
    );
  }

  if (!user) {
    router.push('/signin');
    return null;
  }

  const detectFileType = (file: File): FileType => {
    const extension = file.name.split('.').pop()?.toLowerCase();
    const mimeType = file.type;

    if (mimeType.startsWith('image/') || ['jpg', 'jpeg', 'png', 'heic'].includes(extension || '')) {
      return 'image';
    }
    if (mimeType === 'application/pdf' || extension === 'pdf') {
      return 'pdf';
    }
    if (
      mimeType.includes('csv') ||
      mimeType.includes('spreadsheet') ||
      mimeType.includes('excel') ||
      ['csv', 'xlsx', 'xls'].includes(extension || '')
    ) {
      return 'csv';
    }
    return 'unknown';
  };

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const files = Array.from(e.target.files || []);
    setUploadedFiles(files);
    setParsedData(null);
    setSelectedEntries(new Set());
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    const files = Array.from(e.dataTransfer.files);
    setUploadedFiles(files);
    setParsedData(null);
    setSelectedEntries(new Set());
  };

  const extractDateFromImage = async (file: File): Promise<string> => {
    try {
      // Dynamically import exifr only when needed
      const exifr = (await import('exifr')).default;

      // Try to extract EXIF data
      const exifData = await exifr.parse(file, {
        pick: ['DateTimeOriginal', 'CreateDate', 'ModifyDate'],
      });

      if (exifData) {
        const date = exifData.DateTimeOriginal || exifData.CreateDate || exifData.ModifyDate;
        if (date) {
          return format(new Date(date), 'yyyy-MM-dd');
        }
      }
    } catch (error) {
      console.log('Could not extract EXIF data:', error);
    }

    // Fallback to file last modified date
    return format(new Date(file.lastModified), 'yyyy-MM-dd');
  };

  const parsePDFWithOpenAI = async (file: File): Promise<ParsedData | null> => {
    try {
      const formData = new FormData();
      formData.append('file', file);

      const response = await fetch('/api/parse-pdf', {
        method: 'POST',
        body: formData,
      });

      if (!response.ok) {
        const errorData = await response.json();
        console.error('PDF parsing error response:', errorData);

        // Check for specific error types
        if (errorData.error?.includes('OpenAI API key not configured')) {
          throw new Error(
            'PDF parsing requires an OpenAI API key. Please set OPENAI_API_KEY in your environment variables.',
          );
        } else if (errorData.error?.includes('Could not extract text')) {
          throw new Error(
            'Could not extract text from PDF. The file might be image-based or corrupted.',
          );
        } else if (errorData.details?.includes('rate limit')) {
          throw new Error('OpenAI rate limit exceeded. Please try again in a few moments.');
        }

        throw new Error(errorData.error || errorData.details || 'Failed to parse PDF');
      }

      const result = await response.json();

      if (result.success && result.data) {
        const data = result.data;
        return {
          type: 'body_composition',
          entries: [
            {
              date: data.date || format(new Date(), 'yyyy-MM-dd'),
              weight: data.weight,
              weight_unit: data.weight_unit || 'kg',
              body_fat_percentage: data.body_fat_percentage,
              muscle_mass: data.muscle_mass,
              waist: data.waist,
              hip: data.hip,
              notes: data.notes || `${data.source || 'Body Composition'} Report`,
            },
          ],
          metadata: {
            source: data.source || result.filename,
            total_entries: 1,
          },
        };
      }
    } catch (error) {
      console.error('Error parsing PDF:', error);
      toast({
        title: 'PDF parsing failed',
        description: 'Could not extract data from PDF. Please check the file and try again.',
        variant: 'destructive',
      });
    }
    return null;
  };

  const parseSpreadsheet = async (file: File): Promise<ParsedData | null> => {
    try {
      type SpreadsheetCell = string | number | boolean | Date | null | undefined;
      let data: SpreadsheetCell[][] = [];

      if (file.name.endsWith('.csv')) {
        // Parse CSV
        const text = await file.text();
        const lines = text.split('\n').filter((line) => line.trim());
        data = lines.map((line) => line.split(',').map((v) => v.trim()));
      } else {
        // Dynamically import Excel parser only when needed
        const readXlsxFile = (await import('read-excel-file/web')).default;

        // Parse Excel into row data
        const rows = await readXlsxFile(file, { dateFormat: 'YYYY-MM-DD' });
        data = rows as SpreadsheetCell[][];
      }

      if (data.length < 2) return null;

      const headers = data[0].map((h) => String(h).toLowerCase());
      const entries: ParsedData['entries'] = [];

      for (let i = 1; i < data.length; i++) {
        const row = data[i];
        if (!row || row.every((cell) => !cell)) continue; // Skip empty rows

        const entry: Partial<ParsedData['entries'][number]> = {};

        headers.forEach((header, index) => {
          const value = row[index];
          if (!value) return;

          if (header.includes('date')) {
            // Handle various date formats
            if (value instanceof Date) {
              entry.date = format(value, 'yyyy-MM-dd');
            } else if (typeof value === 'string' || typeof value === 'number') {
              try {
                entry.date = format(new Date(value), 'yyyy-MM-dd');
              } catch {
                entry.date = String(value);
              }
            } else {
              // Fallback: store as string if we somehow get another type
              entry.date = String(value);
            }
          } else if (header.includes('weight')) {
            entry.weight = parseFloat(String(value));
            if (header.includes('kg')) entry.weight_unit = 'kg';
            else if (header.includes('lbs') || header.includes('lb')) entry.weight_unit = 'lbs';
          } else if (
            header.includes('body fat') ||
            header.includes('bf%') ||
            header.includes('body_fat')
          ) {
            entry.body_fat_percentage = parseFloat(String(value));
          } else if (header.includes('muscle')) {
            entry.muscle_mass = parseFloat(String(value));
          } else if (header.includes('waist')) {
            entry.waist = parseFloat(String(value));
          } else if (header.includes('hip')) {
            entry.hip = parseFloat(String(value));
          } else if (header.includes('notes') || header.includes('comment')) {
            entry.notes = String(value);
          }
        });

        if (entry.date && (entry.weight || entry.body_fat_percentage)) {
          entries.push({
            date: entry.date,
            weight: entry.weight,
            weight_unit: entry.weight_unit,
            body_fat_percentage: entry.body_fat_percentage,
            muscle_mass: entry.muscle_mass,
            waist: entry.waist,
            hip: entry.hip,
            notes: entry.notes,
          });
        }
      }

      if (entries.length > 0) {
        // Sort by date
        entries.sort((a, b) => new Date(a.date).getTime() - new Date(b.date).getTime());

        return {
          type: 'weight',
          entries: entries,
          metadata: {
            source: file.name,
            total_entries: entries.length,
            date_range:
              entries.length > 1
                ? {
                    start: entries[0].date,
                    end: entries[entries.length - 1].date,
                  }
                : undefined,
          },
        };
      }
    } catch (error) {
      console.error('Error parsing spreadsheet:', error);
    }
    return null;
  };

  const processFiles = async () => {
    if (uploadedFiles.length === 0) return;

    setIsProcessing(true);
    setProcessingStatus('Analyzing files...');

    try {
      const allEntries: ParsedData['entries'] = [];
      let dataType: ParsedData['type'] = 'weight';
      const sources: string[] = [];

      for (const file of uploadedFiles) {
        const fileType = detectFileType(file);

        if (fileType === 'image') {
          setProcessingStatus(`Extracting date from ${file.name}...`);
          // Process image with EXIF date extraction
          const date = await extractDateFromImage(file);
          const photoUrl = URL.createObjectURL(file);

          allEntries.push({
            date,
            photo_url: photoUrl,
            angle: 'front', // You could enhance this with AI detection
            notes: file.name,
          });
          dataType = 'photos';
          sources.push('Images');
        } else if (fileType === 'pdf') {
          setProcessingStatus(`Analyzing PDF with AI: ${file.name}...`);
          // Process PDF with OpenAI
          const pdfData = await parsePDFWithOpenAI(file);
          if (pdfData && pdfData.entries.length > 0) {
            allEntries.push(...pdfData.entries);
            dataType = 'body_composition';
            sources.push(pdfData.metadata?.source || 'PDF');
          }
        } else if (fileType === 'csv') {
          setProcessingStatus(`Parsing spreadsheet: ${file.name}...`);
          // Process CSV or Excel
          const spreadsheetData = await parseSpreadsheet(file);
          if (spreadsheetData && spreadsheetData.entries.length > 0) {
            allEntries.push(...spreadsheetData.entries);
            sources.push(spreadsheetData.metadata?.source || 'Spreadsheet');
          }
        }
      }

      if (allEntries.length > 0) {
        // Sort entries by date
        allEntries.sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());

        setParsedData({
          type: dataType,
          entries: allEntries,
          metadata: {
            source: sources.join(', '),
            total_entries: allEntries.length,
            date_range:
              allEntries.length > 1
                ? {
                    start: allEntries[allEntries.length - 1].date,
                    end: allEntries[0].date,
                  }
                : undefined,
          },
        });

        // Select all by default
        setSelectedEntries(new Set(Array.from({ length: allEntries.length }, (_, i) => i)));
      } else {
        toast({
          title: 'No data found',
          description: 'Could not extract any data from the uploaded files.',
          variant: 'destructive',
        });
      }
    } catch (error) {
      console.error('Error processing files:', error);
      const errorMessage = error instanceof Error ? error.message : 'Unknown error occurred';

      // Show specific error message for OpenAI API key
      if (
        errorMessage.includes('OpenAI API key') ||
        errorMessage.includes('PDF parsing requires')
      ) {
        toast({
          title: 'Configuration Required',
          description: errorMessage,
          variant: 'destructive',
        });
      } else if (errorMessage.includes('Could not extract text')) {
        toast({
          title: 'PDF Reading Error',
          description: errorMessage,
          variant: 'destructive',
        });
      } else if (errorMessage.includes('rate limit')) {
        toast({
          title: 'Rate Limit Exceeded',
          description: errorMessage,
          variant: 'destructive',
        });
      } else {
        toast({
          title: 'Processing failed',
          description:
            errorMessage || 'There was an error processing your files. Please try again.',
          variant: 'destructive',
        });
      }
    } finally {
      setIsProcessing(false);
      setProcessingStatus('');
    }
  };

  const handleEntryToggle = (index: number) => {
    const newSelected = new Set(selectedEntries);
    if (newSelected.has(index)) {
      newSelected.delete(index);
    } else {
      newSelected.add(index);
    }
    setSelectedEntries(newSelected);
  };

  const handleSelectAll = () => {
    if (selectedEntries.size === parsedData?.entries.length) {
      setSelectedEntries(new Set());
    } else {
      setSelectedEntries(
        new Set(Array.from({ length: parsedData?.entries.length || 0 }, (_, i) => i)),
      );
    }
  };

  const handleImport = async () => {
    if (!parsedData || selectedEntries.size === 0 || !user) return;

    setIsProcessing(true);
    setProcessingStatus('Preparing import...');
    setUploadProgress(0);
    setUploadErrors([]);
    setSuccessCount(0);

    try {
      const supabase = createClient();
      const selectedData = parsedData.entries.filter((_, index) => selectedEntries.has(index));

      if (parsedData.type === 'photos') {
        setProcessingStatus('Starting photo upload...');
        // Upload photos to Supabase Storage first - sequentially to avoid rate limits
        const uploadResults = [];
        let successfulUploads = 0;
        const errors: string[] = [];

        for (let index = 0; index < selectedData.length; index++) {
          const entry = selectedData[index];
          const progress = Math.round(((index + 1) / selectedData.length) * 100);
          setUploadProgress(progress);

          if (!entry.photo_url) {
            uploadResults.push(null);
            continue;
          }

          try {
            setProcessingStatus(`Uploading photo ${index + 1} of ${selectedData.length}...`);

            // Convert blob URL to file
            const response = await fetch(entry.photo_url);
            if (!response.ok) {
              throw new Error(`Failed to fetch photo: ${response.status} ${response.statusText}`);
            }

            const blob = await response.blob();
            if (!blob || blob.size === 0) {
              throw new Error('Invalid photo data: empty blob');
            }

            const fileName = `${user.id}/${Date.now()}-${entry.notes?.replace(/[^a-zA-Z0-9]/g, '-') || 'photo'}.jpg`;

            // Upload to Supabase Storage using our utility
            const { publicUrl, error: uploadError } = await uploadToStorage(
              'photos',
              fileName,
              blob,
              { contentType: 'image/jpeg' },
            );

            if (uploadError) {
              console.error('Upload error details:', {
                error: uploadError,
                fileName,
                blobSize: blob.size,
                blobType: blob.type,
              });
              throw uploadError;
            }

            // Create body metrics entry with photo
            const { error: metricsError } = await supabase.from('body_metrics').insert({
              user_id: user.id,
              date: entry.date,
              photo_url: publicUrl,
              notes: entry.notes,
            });

            if (metricsError) {
              console.error('Metrics error:', metricsError);
              throw metricsError;
            }

            uploadResults.push({ success: true, url: publicUrl });
            successfulUploads++;
            setSuccessCount(successfulUploads);
          } catch (photoError) {
            // Properly extract error details
            const errorMessage =
              photoError instanceof Error
                ? photoError.message
                : typeof photoError === 'string'
                  ? photoError
                  : 'Unknown error occurred';

            console.error(`Error uploading photo ${index + 1}:`, errorMessage);

            // Log full error details for debugging
            if (photoError instanceof Error) {
              console.error('Error details:', {
                message: photoError.message,
                name: photoError.name,
                stack: photoError.stack,
              });
            } else {
              console.error('Non-Error object:', JSON.stringify(photoError, null, 2));
            }

            const errorString = `Photo ${index + 1}: ${errorMessage}`;
            errors.push(errorString);
            setUploadErrors(errors);
            uploadResults.push({ success: false, error: errorMessage, fileName: entry.notes });
          }

          // Add a small delay between uploads to avoid rate limiting
          if (index < selectedData.length - 1) {
            await new Promise((resolve) => setTimeout(resolve, 500));
          }
        }

        const successCount = uploadResults.filter((r) => r?.success).length;
        const failCount = uploadResults.filter((r) => r && !r.success).length;

        if (failCount > 0) {
          // Get first few error messages for display
          const errorMessages = uploadResults
            .filter((r): r is NonNullable<typeof r> => r !== null && !r.success && !!r.error)
            .slice(0, 3)
            .map((r) => r.error)
            .join(', ');

          toast({
            title: 'Some photos failed to upload',
            description: `${successCount} photos imported successfully, ${failCount} failed. Errors: ${errorMessages}`,
            variant: 'default',
          });

          // Log all errors for debugging
          uploadResults
            .filter((r): r is NonNullable<typeof r> => r !== null && !r.success)
            .forEach((result, idx) => {
              console.error(`Failed upload ${idx + 1}:`, result.error);
            });
        }
      } else {
        // Import body composition or weight data
        const metricsData = selectedData.map((entry) => ({
          user_id: user.id,
          date: entry.date,
          weight: entry.weight,
          weight_unit: entry.weight_unit || 'kg',
          body_fat_percentage: entry.body_fat_percentage,
          waist: entry.waist,
          hip: entry.hip,
          notes: entry.notes,
        }));

        const { error } = await supabase.from('body_metrics').insert(metricsData);

        if (error) throw error;
      }

      toast({
        title: 'Import successful!',
        description: `Imported ${selectedEntries.size} entries successfully.`,
      });

      router.push('/dashboard');
    } catch (error) {
      console.error('Import error:', error);
      toast({
        title: 'Import failed',
        description:
          error instanceof Error
            ? error.message
            : 'There was an error saving your data. Please try again.',
        variant: 'destructive',
      });
    } finally {
      setIsProcessing(false);
      setProcessingStatus('');
      setUploadProgress(0);
      setUploadErrors([]);
      setSuccessCount(0);
    }
  };

  const getFileIcon = (fileType: FileType) => {
    switch (fileType) {
      case 'image':
        return <ImageIcon className="h-5 w-5" />;
      case 'pdf':
        return <FileText className="h-5 w-5" aria-hidden="true" />;
      case 'csv':
        return <FileSpreadsheet className="h-5 w-5" aria-hidden="true" />;
      default:
        return <FileText className="h-5 w-5" aria-hidden="true" />;
    }
  };

  return (
    <div className="bg-linear-bg min-h-screen">
      {/* Header */}
      <header className="bg-linear-card border-linear-border sticky top-0 z-10 border-b shadow-sm">
        <div className="container mx-auto px-4 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-4">
              <Link href="/dashboard">
                <Button variant="ghost" size="icon">
                  <ArrowLeft className="h-4 w-4" />
                </Button>
              </Link>
              <h1 className="text-linear-text text-xl font-bold">Smart Import</h1>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="container mx-auto max-w-4xl px-3 py-4 sm:px-4 sm:py-6">
        {!parsedData ? (
          <Card className="bg-linear-card border-linear-border">
            <CardHeader>
              <CardTitle className="text-linear-text">Upload Your Files</CardTitle>
              <CardDescription className="text-linear-text-secondary">
                Drop any files here - photos, PDFs, or spreadsheets. We will figure out what they
                are.
              </CardDescription>
            </CardHeader>
            <CardContent className="space-y-6">
              {/* Upload Area */}
              <div className="relative">
                <input
                  type="file"
                  id="file-upload"
                  className="hidden"
                  multiple
                  accept="image/*,.pdf,.csv,.xlsx,.xls"
                  onChange={handleFileChange}
                />
                <label
                  htmlFor="file-upload"
                  className="border-linear-border hover:bg-linear-card/50 flex h-64 w-full cursor-pointer flex-col items-center justify-center rounded-lg border-2 border-dashed transition-colors"
                  onDrop={handleDrop}
                  onDragOver={(e) => e.preventDefault()}
                >
                  {uploadedFiles.length > 0 ? (
                    <div className="text-center">
                      <CheckCircle className="mx-auto mb-3 h-12 w-12 text-green-500" />
                      <p className="text-linear-text mb-3 font-medium">
                        {uploadedFiles.length} file{uploadedFiles.length > 1 ? 's' : ''} selected
                      </p>
                      <div className="max-h-32 space-y-2 overflow-y-auto px-2">
                        {uploadedFiles.map((file, index) => (
                          <div
                            key={index}
                            className="text-linear-text-secondary flex items-center gap-2 text-sm"
                          >
                            <div className="flex-shrink-0">{getFileIcon(detectFileType(file))}</div>
                            <span className="max-w-[200px] flex-1 truncate sm:max-w-xs">
                              {file.name}
                            </span>
                            <span className="flex-shrink-0 text-xs">
                              ({(file.size / 1024 / 1024).toFixed(1)} MB)
                            </span>
                          </div>
                        ))}
                      </div>
                      <Button variant="link" className="text-linear-purple mt-4">
                        Change Files
                      </Button>
                    </div>
                  ) : (
                    <>
                      <Upload className="text-linear-text-tertiary mb-3 h-12 w-12" />
                      <p className="text-linear-text-secondary mb-1">
                        Drop files here or click to browse
                      </p>
                      <p className="text-linear-text-tertiary text-sm">
                        Photos, DEXA PDFs, CSV spreadsheets - we will handle them all
                      </p>
                    </>
                  )}
                </label>
              </div>

              {/* Process Button */}
              {uploadedFiles.length > 0 && (
                <div className="flex justify-end">
                  <Button
                    onClick={processFiles}
                    disabled={isProcessing}
                    className="bg-linear-purple hover:bg-linear-purple/80"
                  >
                    {isProcessing ? (
                      <>
                        <div className="mr-2 h-4 w-4 animate-spin rounded-full border-2 border-white border-t-transparent" />
                        {processingStatus || 'Analyzing files...'}
                      </>
                    ) : (
                      <>
                        <Upload className="mr-2 h-4 w-4" />
                        Process Files
                      </>
                    )}
                  </Button>
                </div>
              )}

              {/* Info Section */}
              <div className="mt-6 space-y-4">
                <h3 className="text-linear-text text-sm font-medium">Supported File Types</h3>
                <div className="grid gap-3 text-xs sm:text-sm">
                  <div className="flex gap-3">
                    <ImageIcon className="text-linear-text-secondary mt-0.5 h-5 w-5 flex-shrink-0" />
                    <div>
                      <p className="text-linear-text font-medium">Photos (JPG, PNG, HEIC)</p>
                      <p className="text-linear-text-secondary">
                        Automatically extracts date from EXIF data
                      </p>
                    </div>
                  </div>
                  <div className="flex gap-3">
                    <FileText
                      className="text-linear-text-secondary mt-0.5 h-5 w-5 flex-shrink-0"
                      aria-hidden="true"
                    />
                    <div>
                      <p className="text-linear-text font-medium">PDFs (DEXA, InBody, etc.)</p>
                      <p className="text-linear-text-secondary">
                        AI-powered extraction of body composition data
                      </p>
                    </div>
                  </div>
                  <div className="flex gap-3">
                    <FileSpreadsheet
                      className="text-linear-text-secondary mt-0.5 h-5 w-5 flex-shrink-0"
                      aria-hidden="true"
                    />
                    <div>
                      <p className="text-linear-text font-medium">Spreadsheets (CSV, Excel)</p>
                      <p className="text-linear-text-secondary">
                        Import historical tracking data with dates, weight, and body fat
                      </p>
                    </div>
                  </div>
                </div>
              </div>
            </CardContent>
          </Card>
        ) : (
          <div className="space-y-6">
            {/* Summary Card */}
            <Card className="bg-linear-card border-linear-border">
              <CardHeader>
                <div className="flex items-center justify-between">
                  <div>
                    <CardTitle className="text-linear-text">Review Imported Data</CardTitle>
                    <CardDescription className="text-linear-text-secondary">
                      We found {parsedData.entries.length} entries from{' '}
                      {parsedData.metadata?.source}
                    </CardDescription>
                  </div>
                  <Badge variant="secondary">
                    {parsedData.type === 'photos'
                      ? 'Progress Photos'
                      : parsedData.type === 'body_composition'
                        ? 'Body Composition'
                        : 'Weight History'}
                  </Badge>
                </div>
              </CardHeader>
              <CardContent>
                <div className="mb-4 flex items-center justify-between">
                  <div className="flex items-center gap-4 text-sm">
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={handleSelectAll}
                      className="border-linear-border"
                    >
                      {selectedEntries.size === parsedData.entries.length
                        ? 'Deselect All'
                        : 'Select All'}
                    </Button>
                    <span className="text-linear-text-secondary">
                      {selectedEntries.size} of {parsedData.entries.length} selected
                    </span>
                  </div>
                  {parsedData.metadata?.date_range && (
                    <span className="text-linear-text-secondary text-sm">
                      {format(new Date(parsedData.metadata.date_range.start), 'MMM d')} -{' '}
                      {format(new Date(parsedData.metadata.date_range.end), 'MMM d, yyyy')}
                    </span>
                  )}
                </div>

                {/* Data Preview */}
                <div className="border-linear-border overflow-hidden rounded-lg border">
                  {parsedData.type === 'photos' ? (
                    <div className="grid grid-cols-2 gap-4 p-4 md:grid-cols-3">
                      {parsedData.entries.map((entry, index) => (
                        <div
                          key={index}
                          className={`relative cursor-pointer transition-opacity ${
                            selectedEntries.has(index) ? 'opacity-100' : 'opacity-40'
                          }`}
                          onClick={() => handleEntryToggle(index)}
                        >
                          <div className="bg-linear-border relative aspect-[3/4] overflow-hidden rounded-lg">
                            {entry.photo_url && (
                              <img
                                src={entry.photo_url}
                                alt={`From ${format(new Date(entry.date), 'MMM d, yyyy')}`}
                                className="h-full w-full object-cover"
                              />
                            )}
                          </div>
                          <div className="absolute top-2 right-2">
                            <div
                              className={`flex h-6 w-6 items-center justify-center rounded-full border-2 ${
                                selectedEntries.has(index)
                                  ? 'bg-linear-purple border-linear-purple'
                                  : 'bg-linear-bg border-linear-border'
                              }`}
                            >
                              {selectedEntries.has(index) && (
                                <Check className="h-3 w-3 text-white" />
                              )}
                            </div>
                          </div>
                          <div className="mt-2 text-center">
                            <p className="text-linear-text-secondary text-xs">{entry.angle}</p>
                            <p className="text-linear-text text-xs">
                              {format(new Date(entry.date), 'MMM d')}
                            </p>
                          </div>
                        </div>
                      ))}
                    </div>
                  ) : (
                    <div className="divide-linear-border divide-y">
                      {parsedData.entries.map((entry, index) => (
                        <div
                          key={index}
                          className={`hover:bg-linear-card/50 flex cursor-pointer items-center gap-2 p-3 transition-colors sm:gap-4 sm:p-4 ${
                            selectedEntries.has(index) ? 'bg-linear-purple/5' : ''
                          }`}
                          onClick={() => handleEntryToggle(index)}
                        >
                          <div
                            className={`flex h-5 w-5 flex-shrink-0 items-center justify-center rounded border-2 ${
                              selectedEntries.has(index)
                                ? 'bg-linear-purple border-linear-purple'
                                : 'border-linear-border'
                            }`}
                          >
                            {selectedEntries.has(index) && <Check className="h-3 w-3 text-white" />}
                          </div>
                          <div className="grid flex-1 grid-cols-1 gap-2 sm:grid-cols-2 sm:gap-4 md:grid-cols-4">
                            <div>
                              <p className="text-linear-text-secondary text-xs">Date</p>
                              <p className="text-linear-text text-sm font-medium">
                                {format(new Date(entry.date), 'MMM d, yyyy')}
                              </p>
                            </div>
                            {entry.weight && (
                              <div>
                                <p className="text-linear-text-secondary text-xs">Weight</p>
                                <p className="text-linear-text text-sm font-medium">
                                  {entry.weight} {entry.weight_unit || 'kg'}
                                </p>
                              </div>
                            )}
                            {entry.body_fat_percentage && (
                              <div>
                                <p className="text-linear-text-secondary text-xs">Body Fat</p>
                                <p className="text-linear-text text-sm font-medium">
                                  {entry.body_fat_percentage}%
                                </p>
                              </div>
                            )}
                            {entry.muscle_mass && (
                              <div>
                                <p className="text-linear-text-secondary text-xs">Muscle Mass</p>
                                <p className="text-linear-text text-sm font-medium">
                                  {entry.muscle_mass} kg
                                </p>
                              </div>
                            )}
                          </div>
                        </div>
                      ))}
                    </div>
                  )}
                </div>
              </CardContent>
            </Card>

            {/* Action Buttons */}
            <div className="flex flex-col gap-3 sm:flex-row">
              <Button
                variant="outline"
                onClick={() => {
                  setParsedData(null);
                  setUploadedFiles([]);
                  setSelectedEntries(new Set());
                }}
                className="border-linear-border w-full sm:w-auto"
              >
                <XIcon className="mr-2 h-4 w-4" />
                Start Over
              </Button>
              <Button
                onClick={handleImport}
                disabled={selectedEntries.size === 0}
                className="bg-linear-purple hover:bg-linear-purple/80 w-full sm:flex-1"
              >
                <CheckCircle className="mr-2 h-4 w-4" />
                Import {selectedEntries.size} {selectedEntries.size === 1 ? 'Entry' : 'Entries'}
              </Button>
            </div>
          </div>
        )}
      </main>

      {/* Upload Progress Dialog */}
      <Dialog open={isProcessing} onOpenChange={() => {}}>
        <DialogContent className="bg-linear-card border-linear-border sm:max-w-md">
          <DialogHeader>
            <DialogTitle className="text-linear-text">
              {parsedData?.type === 'photos' ? 'Uploading Photos' : 'Importing Data'}
            </DialogTitle>
            <DialogDescription className="text-linear-text-secondary">
              {processingStatus}
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-4">
            {/* Progress Bar */}
            <div className="space-y-2">
              <Progress value={uploadProgress} className="h-2" />
              <div className="text-linear-text-secondary flex justify-between text-sm">
                <span>{successCount} successful</span>
                <span>{uploadProgress}%</span>
              </div>
            </div>

            {/* Loading Animation */}
            <div className="flex justify-center py-4">
              <Loader2 className="text-linear-purple h-8 w-8 animate-spin" />
            </div>

            {/* Errors */}
            {uploadErrors.length > 0 && (
              <div className="max-h-32 space-y-1 overflow-y-auto rounded-lg bg-red-500/10 p-3">
                <div className="mb-2 flex items-center gap-2 text-red-500">
                  <AlertCircle className="h-4 w-4" />
                  <span className="text-sm font-medium">Errors:</span>
                </div>
                {uploadErrors.map((error, index) => (
                  <p key={index} className="text-xs text-red-400">
                    {error}
                  </p>
                ))}
              </div>
            )}

            {/* Info Text */}
            <p className="text-linear-text-tertiary text-center text-xs">
              Please keep this window open until the upload completes
            </p>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  );
}
