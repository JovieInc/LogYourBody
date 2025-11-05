//
// PhotoMetadataService.swift
// LogYourBody
//
import Foundation
import Photos
import ImageIO
import CoreData

class PhotoMetadataService {
    static let shared = PhotoMetadataService()
    private init() {}

    /// Extract EXIF orientation from photo metadata
    func extractOrientation(from data: Data) -> CGImagePropertyOrientation {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return .up
        }

        // Get orientation value (1-8)
        if let orientationValue = properties[kCGImagePropertyOrientation as String] as? UInt32 {
            return CGImagePropertyOrientation(rawValue: orientationValue) ?? .up
        }

        return .up
    }

    /// Extract date from photo metadata or PHAsset
    func extractDate(from data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else {
            return nil
        }

        // Try to get EXIF date
        if let exifDict = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
            // Try DateTimeOriginal first (when photo was taken)
            if let dateString = exifDict[kCGImagePropertyExifDateTimeOriginal as String] as? String {
                return parseExifDate(dateString)
            }
            // Fall back to DateTimeDigitized
            if let dateString = exifDict[kCGImagePropertyExifDateTimeDigitized as String] as? String {
                return parseExifDate(dateString)
            }
        }

        // Try TIFF date
        if let tiffDict = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any],
           let dateString = tiffDict[kCGImagePropertyTIFFDateTime as String] as? String {
            return parseExifDate(dateString)
        }

        return nil
    }
    
    /// Extract date from PHAsset
    func extractDate(from asset: PHAsset) -> Date {
        // PHAsset.creationDate is when the photo was taken
        return asset.creationDate ?? Date()
    }
    
    /// Parse EXIF date string format: "yyyy:MM:dd HH:mm:ss"
    private func parseExifDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.timeZone = TimeZone.current
        return formatter.date(from: dateString)
    }
    
    /// Find closest body metrics entry for a given date
    func findClosestMetrics(for date: Date, in metrics: [BodyMetrics], maxDaysDifference: Int = 7) -> BodyMetrics? {
        guard !metrics.isEmpty else { return nil }
        
        let calendar = Calendar.current
        let targetStartOfDay = calendar.startOfDay(for: date)
        
        // Find metrics within the max days difference
        let closeMetrics = metrics.filter { metric in
            let metricStartOfDay = calendar.startOfDay(for: metric.date)
            let daysDifference = abs(calendar.dateComponents([.day], from: targetStartOfDay, to: metricStartOfDay).day ?? Int.max)
            return daysDifference <= maxDaysDifference
        }
        
        // Return the closest one
        return closeMetrics.min { metric1, metric2 in
            abs(metric1.date.timeIntervalSince(date)) < abs(metric2.date.timeIntervalSince(date))
        }
    }
    
    /// Create or update body metrics for a specific date
    func createOrUpdateMetrics(for date: Date, photoUrl: String? = nil, weight: Double? = nil, bodyFatPercentage: Double? = nil, userId: String) -> BodyMetrics {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        
        // Check if metrics already exist for this date
        let existingMetrics = CoreDataManager.shared.fetchBodyMetrics(for: userId, from: startOfDay, to: calendar.date(byAdding: .day, value: 1, to: startOfDay))
            .first?.toBodyMetrics()
        
        if let existing = existingMetrics {
            // Update existing metrics
            let updated = BodyMetrics(
                id: existing.id,
                userId: userId,
                date: existing.date,
                weight: weight ?? existing.weight,
                weightUnit: existing.weightUnit ?? "kg",
                bodyFatPercentage: bodyFatPercentage ?? existing.bodyFatPercentage,
                bodyFatMethod: existing.bodyFatMethod,
                muscleMass: existing.muscleMass,
                boneMass: existing.boneMass,
                notes: existing.notes,
                photoUrl: photoUrl ?? existing.photoUrl,
                dataSource: existing.dataSource,
                createdAt: existing.createdAt,
                updatedAt: Date()
            )
            
            CoreDataManager.shared.saveBodyMetrics(updated, userId: userId)
            return updated
        } else {
            // Create new metrics
            let new = BodyMetrics(
                id: UUID().uuidString,
                userId: userId,
                date: startOfDay,
                weight: weight,
                weightUnit: "kg",
                bodyFatPercentage: bodyFatPercentage,
                bodyFatMethod: nil,
                muscleMass: nil,
                boneMass: nil,
                notes: nil,
                photoUrl: photoUrl,
                dataSource: "Manual",
                createdAt: Date(),
                updatedAt: Date()
            )
            
            CoreDataManager.shared.saveBodyMetrics(new, userId: userId)
            return new
        }
    }
    
    /// Estimate weight based on nearby entries
    func estimateWeight(for date: Date, metrics: [BodyMetrics]) -> (value: Double, isEstimated: Bool)? {
        let sortedMetrics = metrics.filter { $0.weight != nil }.sorted { $0.date < $1.date }
        guard !sortedMetrics.isEmpty else { return nil }
        
        // Find metrics before and after the date
        let before = sortedMetrics.last { $0.date <= date }
        let after = sortedMetrics.first { $0.date > date }
        
        if let beforeMetric = before, let afterMetric = after,
           let beforeWeight = beforeMetric.weight, let afterWeight = afterMetric.weight {
            // Linear interpolation between two points
            let totalInterval = afterMetric.date.timeIntervalSince(beforeMetric.date)
            let progressInterval = date.timeIntervalSince(beforeMetric.date)
            let progress = progressInterval / totalInterval
            
            let estimatedWeight = beforeWeight + (afterWeight - beforeWeight) * progress
            return (round(estimatedWeight * 10) / 10, true)
        } else if let closestMetric = before ?? after {
            // Use the closest available metric
            return (closestMetric.weight ?? 0, true)
        }
        
        return nil
    }
    
    /// Estimate body fat percentage based on nearby entries
    func estimateBodyFat(for date: Date, metrics: [BodyMetrics]) -> (value: Double, isEstimated: Bool)? {
        let sortedMetrics = metrics.filter { $0.bodyFatPercentage != nil }.sorted { $0.date < $1.date }
        guard !sortedMetrics.isEmpty else { return nil }
        
        // Find metrics before and after the date
        let before = sortedMetrics.last { $0.date <= date }
        let after = sortedMetrics.first { $0.date > date }
        
        if let beforeMetric = before, let afterMetric = after,
           let beforeBF = beforeMetric.bodyFatPercentage, let afterBF = afterMetric.bodyFatPercentage {
            // Linear interpolation between two points
            let totalInterval = afterMetric.date.timeIntervalSince(beforeMetric.date)
            let progressInterval = date.timeIntervalSince(beforeMetric.date)
            let progress = progressInterval / totalInterval
            
            let estimatedBF = beforeBF + (afterBF - beforeBF) * progress
            return (round(estimatedBF * 10) / 10, true)
        } else if let closestMetric = before ?? after {
            // Use the closest available metric
            return (closestMetric.bodyFatPercentage ?? 0, true)
        }
        
        return nil
    }
}
