#!/bin/bash

# Script to remove duplicate files from Xcode project

PROJECT_FILE="LogYourBody.xcodeproj/project.pbxproj"

# List of duplicate files to remove from build phase
DUPLICATE_FILES=(
    "EmailVerificationView.swift"
    "DietPhaseHistoryView.swift" 
    "ImageProcessingService.swift"
    "AppVersion.swift"
    "LiquidGlassComponents.swift"
    "BulkImportManager.swift"
    "PhotoLibraryScanner.swift"
    "NotificationsStepView.swift"
    "HealthKitStepView.swift"
    "WelcomeStepView.swift"
    "CompletionStepView.swift"
    "OnboardingContainerView.swift"
    "SyncStatusView.swift"
    "BulkPhotoImportView.swift"
    "IntegrationsView.swift"
)

echo "Fixing duplicate files in Xcode project..."

# Create backup
cp "$PROJECT_FILE" "$PROJECT_FILE.backup"

# For each duplicate file, find and remove duplicate entries
for file in "${DUPLICATE_FILES[@]}"; do
    echo "Processing $file..."
    
    # Find all occurrences of the file in PBXBuildFile section
    file_refs=$(grep -n "\/\* $file in Sources \*\/" "$PROJECT_FILE" | cut -d: -f1)
    
    # If we have more than one occurrence, remove the duplicates
    ref_count=$(echo "$file_refs" | wc -l)
    if [ $ref_count -gt 1 ]; then
        echo "  Found $ref_count references to $file, removing duplicates..."
        
        # Keep the first occurrence, remove the rest
        first_line=$(echo "$file_refs" | head -n 1)
        duplicate_lines=$(echo "$file_refs" | tail -n +2)
        
        # For each duplicate, find the corresponding PBXBuildFile entry and remove it
        for line_num in $duplicate_lines; do
            # Find the start of the PBXBuildFile entry (usually 1-2 lines before)
            start_line=$((line_num - 2))
            
            # Use sed to remove the duplicate entry
            sed -i '' "${start_line},${line_num}d" "$PROJECT_FILE"
            
            # Adjust line numbers for subsequent deletions
            file_refs=$(echo "$file_refs" | awk -v deleted=$line_num '{if ($1 > deleted) print $1-3; else print $1}')
        done
    fi
done

echo "Done! Project file has been updated."
echo "Backup saved as $PROJECT_FILE.backup"
