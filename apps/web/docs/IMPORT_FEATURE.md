# Smart Import Feature

The Smart Import feature allows users to bulk import their body composition data from various file formats with intelligent data extraction.

## Supported File Types

### 1. Images (Progress Photos)

- **Formats**: JPG, PNG, HEIC
- **Features**:
  - Automatic date extraction from EXIF metadata
  - Falls back to file modification date if EXIF is unavailable
  - Stores photos in Supabase Storage with user-specific folders
  - Creates body metrics entries with photo URLs

### 2. PDFs (Body Composition Reports)

- **Formats**: PDF files from DEXA scans, InBody, or similar devices
- **Features**:
  - AI-powered text extraction using OpenAI GPT-4
  - Automatically identifies and extracts:
    - Scan date
    - Weight (kg/lbs)
    - Body fat percentage
    - Muscle mass
    - Bone mass
    - Visceral fat rating
    - Basal metabolic rate
    - Body measurements (waist, hip, chest, arms, thighs)
  - Preserves scan type and source information

### 3. Spreadsheets (Historical Data)

- **Formats**: CSV, Excel (XLSX, XLS)
- **Features**:
  - Flexible column detection (case-insensitive)
  - Supports various date formats
  - Automatically detects:
    - Date columns
    - Weight (with unit detection)
    - Body fat percentage
    - Muscle mass
    - Body measurements
    - Notes/comments
  - Handles empty rows gracefully
  - Preserves data chronology

## Technical Implementation

### Frontend (`/src/app/import/page.tsx`)

- Drag-and-drop file upload interface
- Real-time processing status updates
- Preview of extracted data before import
- Selective import with checkboxes
- Bulk operations support

### Backend (`/src/app/api/parse-pdf/route.ts`)

- OpenAI API integration for PDF analysis
- Structured data extraction with JSON response format
- Error handling and validation

### Dependencies

- `exifr`: EXIF data extraction from images
- `openai`: OpenAI API client for PDF analysis
- `pdf-parse`: PDF text extraction
- `read-excel-file`: Excel file parsing

## Environment Variables

Required for PDF parsing:

```env
OPENAI_API_KEY=your-openai-api-key
```

## Database Schema

The import feature works with the existing `body_metrics` table:

- Stores extracted measurements and calculations
- Links to uploaded photos via `photo_url`
- Preserves original data source in `notes` field

## Storage Configuration

Photos are stored in the `photos` bucket in Supabase Storage:

- User-specific folders: `{user_id}/{timestamp}-{filename}.jpg`
- Public read access for sharing
- Authenticated write/delete access

## Usage Flow

1. User navigates to `/import`
2. Drops or selects files (multiple files supported)
3. System analyzes files and extracts data
4. User reviews extracted data
5. User selects which entries to import
6. Data is saved to database and storage
7. User is redirected to dashboard

## Error Handling

- Invalid file types are rejected with user feedback
- Failed PDF parsing shows error message
- Network errors are caught and displayed
- Partial imports are prevented (all-or-nothing)

## Future Enhancements

- AI-powered angle detection for photos (front/side/back)
- Support for more PDF formats (BodPod, etc.)
- Batch photo organization by date
- Duplicate detection and merging
- Progress tracking during large imports
