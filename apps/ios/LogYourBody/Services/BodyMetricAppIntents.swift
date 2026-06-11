//
// BodyMetricAppIntents.swift
// LogYourBody
//
import AppIntents
import Foundation
import SwiftUI

enum BodyMetricIntentWeightUnit: String, AppEnum {
    case pounds
    case kilograms

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Weight Unit")
    static var caseDisplayRepresentations: [BodyMetricIntentWeightUnit: DisplayRepresentation] = [
        .pounds: DisplayRepresentation(title: "Pounds", subtitle: "lbs"),
        .kilograms: DisplayRepresentation(title: "Kilograms", subtitle: "kg")
    ]

    var storageUnit: String {
        switch self {
        case .pounds:
            return "lbs"
        case .kilograms:
            return "kg"
        }
    }
}

struct LogWeightIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Weight"
    static var description = IntentDescription("Log a body weight measurement in LogYourBody.")
    static var openAppWhenRun = false
    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$weight) \(\.$unit)")
    }

    @Parameter(
        title: "Weight",
        requestValueDialog: "What weight do you want to log?"
    )
    var weight: Double

    @Parameter(title: "Unit", default: .pounds)
    var unit: BodyMetricIntentWeightUnit

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try await BodyMetricLoggingService.shared.log(
            weight: String(weight),
            bodyFat: nil,
            unit: unit.storageUnit
        )

        return .result(dialog: IntentDialog(stringLiteral: result.dialog))
    }
}

struct LogBodyFatIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Body Fat"
    static var description = IntentDescription("Log a body fat percentage in LogYourBody.")
    static var openAppWhenRun = false
    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$bodyFatPercentage)% body fat")
    }

    @Parameter(
        title: "Body Fat Percentage",
        requestValueDialog: "What body fat percentage do you want to log?"
    )
    var bodyFatPercentage: Double

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = try await BodyMetricLoggingService.shared.log(
            weight: nil,
            bodyFat: String(bodyFatPercentage),
            unit: MeasurementSystem.preferredFromDefaults.weightUnit
        )

        return .result(dialog: IntentDialog(stringLiteral: result.dialog))
    }
}

struct ShowLatestMetricsIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Latest Metrics"
    static var description = IntentDescription("Show the latest logged weight and body fat values.")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let latest = try await BodyMetricLoggingService.shared.latestMetricsSummary()

        return .result(dialog: IntentDialog(stringLiteral: latest.dialog)) {
            LatestMetricsIntentSnippet(summary: latest)
        }
    }
}

struct LatestMetricsIntentSnippet: View {
    let summary: BodyMetricLatestSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Latest Metrics")
                .font(.headline)

            Text(summary.dialog)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
    }
}

struct LogYourBodyAppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LogWeightIntent(),
            phrases: [
                "Log my weight in \(.applicationName)",
                "Record my weight with \(.applicationName)"
            ],
            shortTitle: "Log Weight",
            systemImageName: "scalemass"
        )

        AppShortcut(
            intent: LogBodyFatIntent(),
            phrases: [
                "Log my body fat in \(.applicationName)",
                "Record body fat with \(.applicationName)"
            ],
            shortTitle: "Log Body Fat",
            systemImageName: "percent"
        )

        AppShortcut(
            intent: ShowLatestMetricsIntent(),
            phrases: [
                "Show my latest metrics in \(.applicationName)",
                "Show my current weight in \(.applicationName)"
            ],
            shortTitle: "Latest Metrics",
            systemImageName: "chart.line.uptrend.xyaxis"
        )
    }
}
