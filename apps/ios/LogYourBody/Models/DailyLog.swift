//
// DailyLog.swift
// LogYourBody
//
import Foundation

struct DailyLog: Identifiable, Codable {
    let id: String
    let userId: String
    let date: Date
    let weight: Double?
    let weightUnit: String?
    let stepCount: Int?
    let notes: String?
    let createdAt: Date
    let updatedAt: Date

    init(
        id: String = UUID().uuidString,
        userId: String,
        date: Date,
        weight: Double? = nil,
        weightUnit: String? = nil,
        stepCount: Int? = nil,
        notes: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.date = date
        self.weight = weight
        self.weightUnit = weightUnit
        self.stepCount = stepCount
        self.notes = notes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var formattedWeight: String? {
        guard let weight = weight else { return nil }
        return String(format: "%.1f", weight)
    }

    var formattedSteps: String? {
        guard let stepCount = stepCount else { return nil }
        return NumberFormatter.localizedString(from: NSNumber(value: stepCount), number: .decimal)
    }

    var displayWeightUnit: String {
        weightUnit ?? "kg"
    }

    var hasData: Bool {
        weight != nil || stepCount != nil
    }
}

extension DailyLog {
    static var mock: DailyLog {
        DailyLog(
            userId: "test-user",
            date: Date(),
            weight: 75.5,
            weightUnit: "kg",
            stepCount: 8_500,
            notes: "Morning weight and good walking day"
        )
    }

    static var mockArray: [DailyLog] {
        let calendar = Calendar.current
        let today = Date()

        return [
            DailyLog(
                id: "1",
                userId: "test",
                date: calendar.date(byAdding: .day, value: -6, to: today)!,
                weight: 75.5,
                weightUnit: "kg",
                stepCount: 8_200
            ),
            DailyLog(
                id: "2",
                userId: "test",
                date: calendar.date(byAdding: .day, value: -5, to: today)!,
                weight: 75.2,
                weightUnit: "kg",
                stepCount: 9_100
            ),
            DailyLog(
                id: "3",
                userId: "test",
                date: calendar.date(byAdding: .day, value: -4, to: today)!,
                weight: nil,
                weightUnit: nil,
                stepCount: 7_800
            ),
            DailyLog(
                id: "4",
                userId: "test",
                date: calendar.date(byAdding: .day, value: -3, to: today)!,
                weight: 74.8,
                weightUnit: "kg",
                stepCount: 12_000
            ),
            DailyLog(
                id: "5",
                userId: "test",
                date: calendar.date(byAdding: .day, value: -2, to: today)!,
                weight: nil,
                weightUnit: nil,
                stepCount: 6_500
            ),
            DailyLog(
                id: "6",
                userId: "test",
                date: calendar.date(byAdding: .day, value: -1, to: today)!,
                weight: 74.5,
                weightUnit: "kg",
                stepCount: 10_200
            ),
            DailyLog(
                id: "7",
                userId: "test",
                date: today,
                weight: nil,
                weightUnit: nil,
                stepCount: 3_400 // Today so far
            )
        ]
    }
}
