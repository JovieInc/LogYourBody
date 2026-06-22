import { format } from 'date-fns';
import { FileSpreadsheet, FileText, Image as ImageIcon } from 'lucide-react';
import { toast } from '@/hooks/use-toast';

export type FileType = 'image' | 'pdf' | 'csv' | 'unknown';

type WeightUnit = 'kg' | 'lbs';

export interface ParsedData {
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

export const detectFileType = (file: File): FileType => {
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

export const extractDateFromImage = async (file: File): Promise<string> => {
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

export const parsePDFWithOpenAI = async (file: File): Promise<ParsedData | null> => {
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

export const parseSpreadsheet = async (file: File): Promise<ParsedData | null> => {
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
      const readXlsxFile = (await import('read-excel-file')).default;

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

export const getFileIcon = (fileType: FileType) => {
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
