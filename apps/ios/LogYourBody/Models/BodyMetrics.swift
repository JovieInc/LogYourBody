//
// BodyMetrics.swift
// LogYourBody
//
import Foundation

struct BodyMetrics: Identifiable, Codable, Equatable {
    private static let logger = AppLogger(category: "bodyMetrics")
    private static let validWeightUnits: Set<String> = ["kg", "lbs"]
    private static let maxWeightLbs = 1_000.0
    private static let maxBodyFatPercentage = 70.0

    let id: String
    let userId: String
    let date: Date
    let weight: Double?
    let weightUnit: String?
    let bodyFatPercentage: Double?
    let bodyFatMethod: String?
    let muscleMass: Double?
    let boneMass: Double?
    let waistCm: Double?
    let hipCm: Double?
    let waistUnit: String?
    let notes: String?
    let photoUrl: String?
    let dataSource: String?
    let createdAt: Date
    let updatedAt: Date

    init(
        id: String,
        userId: String,
        date: Date,
        weight: Double?,
        weightUnit: String?,
        bodyFatPercentage: Double?,
        bodyFatMethod: String?,
        muscleMass: Double?,
        boneMass: Double?,
        waistCm: Double? = nil,
        hipCm: Double? = nil,
        waistUnit: String? = nil,
        notes: String?,
        photoUrl: String?,
        dataSource: String?,
        createdAt: Date,
        updatedAt: Date
    ) {
        let validatedWeightUnit = Self.validatedWeightUnit(weightUnit)

        self.id = id
        self.userId = userId
        self.date = date
        self.weight = Self.validatedWeight(weight, unit: validatedWeightUnit)
        self.weightUnit = validatedWeightUnit
        self.bodyFatPercentage = Self.validatedBodyFatPercentage(bodyFatPercentage)
        self.bodyFatMethod = bodyFatMethod
        self.muscleMass = muscleMass
        self.boneMass = boneMass
        self.waistCm = Self.positiveMeasurement(waistCm, label: "waistCm")
        self.hipCm = Self.positiveMeasurement(hipCm, label: "hipCm")
        self.waistUnit = waistUnit
        self.notes = notes
        self.photoUrl = photoUrl
        self.dataSource = dataSource
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            id: try container.decode(String.self, forKey: .id),
            userId: try container.decode(String.self, forKey: .userId),
            date: try container.decode(Date.self, forKey: .date),
            weight: try container.decodeIfPresent(Double.self, forKey: .weight),
            weightUnit: try container.decodeIfPresent(String.self, forKey: .weightUnit),
            bodyFatPercentage: try container.decodeIfPresent(Double.self, forKey: .bodyFatPercentage),
            bodyFatMethod: try container.decodeIfPresent(String.self, forKey: .bodyFatMethod),
            muscleMass: try container.decodeIfPresent(Double.self, forKey: .muscleMass),
            boneMass: try container.decodeIfPresent(Double.self, forKey: .boneMass),
            waistCm: try container.decodeIfPresent(Double.self, forKey: .waistCm),
            hipCm: try container.decodeIfPresent(Double.self, forKey: .hipCm),
            waistUnit: try container.decodeIfPresent(String.self, forKey: .waistUnit),
            notes: try container.decodeIfPresent(String.self, forKey: .notes),
            photoUrl: try container.decodeIfPresent(String.self, forKey: .photoUrl),
            dataSource: try container.decodeIfPresent(String.self, forKey: .dataSource),
            createdAt: try container.decode(Date.self, forKey: .createdAt),
            updatedAt: try container.decode(Date.self, forKey: .updatedAt)
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case date
        case weight
        case weightUnit = "weight_unit"
        case bodyFatPercentage = "body_fat_percentage"
        case bodyFatMethod = "body_fat_method"
        case muscleMass = "muscle_mass"
        case boneMass = "bone_mass"
        case waistCm = "waist_circumference"
        case hipCm = "hip_circumference"
        case waistUnit = "waist_unit"
        case notes
        case photoUrl = "photo_url"
        case dataSource = "data_source"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    private static func validatedWeightUnit(_ unit: String?) -> String? {
        guard let unit else {
            return nil
        }

        let normalizedUnit = unit.lowercased()
        guard validWeightUnits.contains(normalizedUnit) else {
            logger.info("Discarding weight with invalid unit '\(unit)'")
            return nil
        }

        return normalizedUnit
    }

    private static func validatedWeight(_ weight: Double?, unit: String?) -> Double? {
        guard let weight else {
            return nil
        }

        guard let unit else {
            logger.info("Discarding weight value because weight_unit is missing or invalid")
            return nil
        }

        guard weight > 0 else {
            logger.info("Discarding non-positive weight value \(weight)")
            return nil
        }

        let weightInLbs = MetricsFormatter.convertWeight(value: weight, from: unit, to: "lbs")
        guard weightInLbs <= maxWeightLbs else {
            logger.info("Discarding out-of-range weight value \(weight) \(unit)")
            return nil
        }

        return weight
    }

    private static func validatedBodyFatPercentage(_ value: Double?) -> Double? {
        guard let value else {
            return nil
        }

        guard value > 0, value <= maxBodyFatPercentage else {
            logger.info("Discarding out-of-range body fat value \(value)")
            return nil
        }

        return value
    }

    private static func positiveMeasurement(_ value: Double?, label: String) -> Double? {
        guard let value else {
            return nil
        }

        guard value > 0 else {
            logger.info("Discarding non-positive \(label) value \(value)")
            return nil
        }

        return value
    }
}
