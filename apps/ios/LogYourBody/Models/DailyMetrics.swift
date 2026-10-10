//
// DailyMetrics.swift
// LogYourBody
//
import Foundation
import CoreFoundation

struct DailyMetrics: Identifiable, Codable {
    let id: String
    let userId: String
    let date: Date
    let steps: Int?
    let notes: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case steps
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Matches CachedDailyMetrics.steps without rounding or silently discarding invalid input.
enum DailyStepCountPolicy {
    enum ValidationError: LocalizedError {
        case invalidSteps

        var errorDescription: String? {
            "Step count must be a supported nonnegative whole number."
        }
    }

    static func storedSteps(_ value: Int?) throws -> Int32 {
        guard let value else { return 0 }
        guard value >= 0, let steps = Int32(exactly: value) else {
            throw ValidationError.invalidSteps
        }
        return steps
    }

    static func storedRemoteSteps(_ value: Any?) throws -> Int32 {
        guard let value, !(value is NSNull) else { return 0 }
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              number.doubleValue >= 0,
              let steps = Int32(exactly: number.doubleValue),
              number.compare(NSDecimalNumber(value: steps)) == .orderedSame else {
            throw ValidationError.invalidSteps
        }
        return steps
    }
}
