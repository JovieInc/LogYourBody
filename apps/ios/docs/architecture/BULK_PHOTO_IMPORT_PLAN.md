# Bulk Photo Import Feature - Implementation Plan

## Overview
A feature to scan the user's photo library for potential progress photos, allowing bulk import with preview and selection capabilities.

## 1. Architecture Components

### 1.1 Core Services
```swift
// PhotoLibraryScanner.swift
- Handles PHPhotoLibrary permissions
- Fetches candidate photos based on criteria
- Manages photo metadata extraction

// ProgressPhotoClassifier.swift  
- CoreML model integration
- Classifies photos as likely progress photos
- Confidence scoring system

// BulkImportManager.swift
- Orchestrates the import process
- Handles background processing
- Manages import state and progress

// PhotoImportQueue.swift
- Queue management for processing
- Handles retries and error recovery
- Progress tracking
```

### 1.2 UI Components
```swift
// BulkImportView.swift
- Main import flow UI
- Permission prompts
- Progress indicators

// PhotoSelectionGridView.swift
- Grid display of candidate photos
- Selection management
- Preview capabilities

// ImportProgressBanner.swift
- Non-blocking progress UI
- Success/failure notifications
- Background task status
```

## 2. Photo Scanning Algorithm

### 2.1 Initial Filtering Criteria
```swift
struct PhotoScanCriteria {
    // Time-based filters
    let dateRange: DateInterval? // Last 2 years by default
    let minimumDaysBetween: Int = 3 // Avoid multiple photos same day
    
    // Technical filters
    let orientation: UIImage.Orientation = .up // Portrait only
    let minimumResolution: CGSize = CGSize(width: 1000, height: 1000)
    let cameraType: CameraType? = .front // Prioritize selfies
    
    // Content filters (via CoreML)
    let minimumConfidence: Float = 0.7
    let excludeScreenshots: Bool = true
    let excludeEdited: Bool = false
}
```

### 2.2 CoreML Integration
```swift
// Use Vision framework with custom CoreML model
// Model trained to identify:
// - Shirtless/sports attire photos
// - Mirror selfies
// - Gym settings
// - Full body visible
// - Consistent poses
```

### 2.3 Smart Grouping
```swift
struct PhotoGroup {
    let date: Date
    let photos: [PHAsset]
    let confidence: Float
    let suggestedPrimary: PHAsset? // Best photo from the group
}

// Group photos by:
// - Same day
// - Similar location (if available)
// - Similar time of day
// - Pose similarity
```

## 3. User Flow

### 3.1 Entry Point (Settings)
```
Settings
├── Sync & Import
│   ├── Apple Health ✓
│   └── Import Progress Photos 📷 [NEW]
```

### 3.2 Import Flow
```
1. Tap "Import Progress Photos"
   → Check photo library permission
   → Request if needed

2. Scanning Phase
   → Show scanning progress
   → "Analyzing X photos..."
   → Background CoreML processing

3. Review & Selection
   → Grid view of candidates
   → Grouped by date
   → Confidence indicators
   → Select all/none options
   → Individual selection

4. Import Confirmation
   → Show count selected
   → Estimated time
   → Storage impact
   → "Import X Photos" button

5. Background Import
   → Return to settings
   → Show progress banner
   → Continue using app
   → Notifications on complete
```

## 4. Implementation Details

### 4.1 Permissions
```swift
// Info.plist
NSPhotoLibraryUsageDescription: "LogYourBody needs access to scan for progress photos"

// PhotoLibraryScanner.swift
func requestPhotoLibraryAccess() async -> Bool {
    let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    return status == .authorized || status == .limited
}
```

### 4.2 Efficient Scanning
```swift
// Fetch in batches to avoid memory issues
let fetchOptions = PHFetchOptions()
fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
fetchOptions.predicate = NSPredicate(format: "mediaType = %d", PHAssetMediaType.image.rawValue)
fetchOptions.fetchLimit = 100 // Process in chunks

// Use PHCachingImageManager for thumbnails
let imageManager = PHCachingImageManager()
imageManager.startCachingImages(for: assets, targetSize: thumbnailSize, contentMode: .aspectFill, options: nil)
```

### 4.3 Background Processing
```swift
// Use URLSession background configuration
let config = URLSessionConfiguration.background(withIdentifier: "bulk-import")
config.isDiscretionary = true
config.sessionSendsLaunchEvents = true

// Process queue
struct ImportTask {
    let asset: PHAsset
    let date: Date
    let localIdentifier: String
    var status: ImportStatus
    var progress: Double
}

enum ImportStatus {
    case pending
    case extracting
    case processing
    case uploading
    case completed
    case failed(Error)
}
```

### 4.4 Progress Tracking
```swift
// Progress state
@Published var importProgress: BulkImportProgress

struct BulkImportProgress {
    let totalPhotos: Int
    let processedPhotos: Int
    let failedPhotos: Int
    let currentPhase: ImportPhase
    
    var percentComplete: Double {
        Double(processedPhotos) / Double(totalPhotos)
    }
}

enum ImportPhase {
    case scanning
    case analyzing
    case importing
    case completing
}
```

## 5. UI Mockups

### 5.1 Settings Entry
```
┌─────────────────────────┐
│ Settings                │
├─────────────────────────┤
│ Sync & Import           │
│                         │
│ 🍎 Apple Health    [✓] │
│ Sync weight & body fat  │
│                         │
│ 📷 Import Photos   [→] │
│ Scan library for photos │
└─────────────────────────┘
```

### 5.2 Selection Grid
```
┌─────────────────────────┐
│ Select Progress Photos  │
│                         │
│ Found 47 potential      │
│ photos to import        │
├─────────────────────────┤
│ [Select All] [Clear]    │
├─────────────────────────┤
│ ┌───┐ ┌───┐ ┌───┐     │
│ │ ✓ │ │ ✓ │ │   │     │
│ └───┘ └───┘ └───┘     │
│ Jan 5  Jan 8  Jan 12   │
│                         │
│ ┌───┐ ┌───┐ ┌───┐     │
│ │ ✓ │ │   │ │ ✓ │     │
│ └───┘ └───┘ └───┘     │
│ Jan 19 Jan 26 Feb 2    │
├─────────────────────────┤
│ [Import 28 Photos]      │
└─────────────────────────┘
```

### 5.3 Progress Banner
```
┌─────────────────────────┐
│ 📥 Importing photos...  │
│ 12 of 28 complete       │
│ ████████░░░░░░░ 43%     │
└─────────────────────────┘
```

## 6. Performance Considerations

### 6.1 Memory Management
- Process photos in batches of 10-20
- Release PHAsset resources after processing
- Use thumbnail sizes for preview (400x400)
- Full resolution only during final import

### 6.2 Battery Optimization
- Pause processing when battery < 20%
- Use low power mode detection
- Schedule heavy processing during charging

### 6.3 Storage Management
- Check available storage before import
- Warn if import would use > 500MB
- Option to optimize photo storage

## 7. Error Handling

### 7.1 Common Scenarios
- No photo library access
- No photos found matching criteria
- Network issues during upload
- Storage full
- App terminated during import

### 7.2 Recovery Strategies
- Save import state to resume
- Retry failed uploads automatically
- Clear error reporting to user
- Option to skip problematic photos

## 8. Privacy & Security

### 8.1 Data Handling
- Never store full resolution locally beyond processing
- Hash photos to detect duplicates
- Respect photo library limited access
- Clear photo data from memory after use

### 8.2 User Control
- Clear selection process
- Ability to cancel at any time
- Delete imported photos later
- No automatic imports

## 9. Future Enhancements

### 9.1 Smart Suggestions
- ML-based date detection from photos
- Automatic weight/BF% estimation
- Pose consistency checking
- Progress tracking insights

### 9.2 Integration Features
- Import from cloud services
- Export to fitness apps
- Social sharing controls
- Comparison tools

## 10. Success Metrics

- Import success rate > 95%
- Average time to import 50 photos < 5 minutes
- User satisfaction with photo selection accuracy
- Minimal battery/performance impact
- < 1% crash rate during import