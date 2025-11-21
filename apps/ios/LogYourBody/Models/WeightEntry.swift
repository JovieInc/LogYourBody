//
// WeightEntry.swift
// LogYourBody
//
import Foundation
struct WeightEntry: Identifiable, Codable {
    let id: String
    let userId: String
    let weight: Double
    let weightUnit: String
    let notes: String?
    let loggedAt: Date

    var formattedWeight: String {
        String(format: "%.1f", weight)
    }

    var displayUnit: String {
        weightUnit == "kg" ? "kg" : "lbs"
    }
}

extension WeightEntry {
    static var mock: WeightEntry {
        WeightEntry(
            id: UUID().uuidString,
            userId: "test-user",
            weight: 75.5,
            weightUnit: "kg",
            notes: "Morning weight",
            loggedAt: Date()
        )
    }

    static var mockArray: [WeightEntry] {
        [
            WeightEntry(
                id: "1",
                userId: "test",
                weight: 75.5,
                weightUnit: "kg",
                notes: nil,
                loggedAt: Date().addingTimeInterval(-86_400 * 7)
            ),
            WeightEntry(
                id: "2",
                userId: "test",
                weight: 75.2,
                weightUnit: "kg",
                notes: nil,
                loggedAt: Date().addingTimeInterval(-86_400 * 6)
            ),
            WeightEntry(
                id: "3",
                userId: "test",
                weight: 75.0,
                weightUnit: "kg",
                notes: nil,
                loggedAt: Date().addingTimeInterval(-86_400 * 5)
            ),
            WeightEntry(
                id: "4",
                userId: "test",
                weight: 74.8,
                weightUnit: "kg",
                notes: nil,
                loggedAt: Date().addingTimeInterval(-86_400 * 4)
            ),
            WeightEntry(
                id: "5",
                userId: "test",
                weight: 74.5,
                weightUnit: "kg",
                notes: nil,
                loggedAt: Date().addingTimeInterval(-86_400 * 3)
            )
        ]
    }
}
