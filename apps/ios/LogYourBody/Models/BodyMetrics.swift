//
// BodyMetrics.swift
// LogYourBody
//
import Foundation

struct BodyMetrics: Identifiable, Codable, Equatable {
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
        self.id = id
        self.userId = userId
        self.date = date
        self.weight = weight
        self.weightUnit = weightUnit
        self.bodyFatPercentage = bodyFatPercentage
        self.bodyFatMethod = bodyFatMethod
        self.muscleMass = muscleMass
        self.boneMass = boneMass
        self.waistCm = waistCm
        self.hipCm = hipCm
        self.waistUnit = waistUnit
        self.notes = notes
        self.photoUrl = photoUrl
        self.dataSource = dataSource
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
}
