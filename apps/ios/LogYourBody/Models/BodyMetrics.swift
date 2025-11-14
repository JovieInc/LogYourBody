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
    let notes: String?
    let photoUrl: String?
    let dataSource: String?
    let createdAt: Date
    let updatedAt: Date
    
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
        case notes
        case photoUrl = "photo_url"
        case dataSource = "data_source"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
