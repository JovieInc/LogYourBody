//
// DailyMetrics.swift
// LogYourBody
//
import Foundation

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
