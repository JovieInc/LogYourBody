//
// Glp1DoseLog.swift
// LogYourBody
//

import Foundation

struct Glp1DoseLog: Identifiable, Codable {
    let id: String
    let userId: String
    let takenAt: Date
    let medicationId: String?
    let doseAmount: Double?
    let doseUnit: String?
    let drugClass: String?
    let brand: String?
    let isCompounded: Bool
    let supplierType: String?
    let supplierName: String?
    let notes: String?
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case takenAt = "taken_at"
        case medicationId = "medication_id"
        case doseAmount = "dose_amount"
        case doseUnit = "dose_unit"
        case drugClass = "drug_class"
        case brand
        case isCompounded = "is_compounded"
        case supplierType = "supplier_type"
        case supplierName = "supplier_name"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}
