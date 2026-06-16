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

enum Glp1DoseHistoryFormatter {
    static func doseText(_ log: Glp1DoseLog) -> String {
        if isRestDay(log) {
            return "Rest day"
        }

        guard let amount = log.doseAmount else {
            return log.doseUnit ?? "Dose"
        }

        let unit = log.doseUnit ?? "dose"
        return "\(numberText(amount)) \(unit)"
    }

    static func numberText(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }

        return String(format: "%.2f", value)
            .replacingOccurrences(of: #"0+$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }

    static func isRestDay(_ log: Glp1DoseLog) -> Bool {
        log.doseAmount == nil && (log.notes?.localizedCaseInsensitiveContains("rest day") ?? false)
    }

    static func dateText(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return "Today"
        }

        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else {
            return mediumDateText(date)
        }

        if calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }

        return mediumDateText(date)
    }

    private static func mediumDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
