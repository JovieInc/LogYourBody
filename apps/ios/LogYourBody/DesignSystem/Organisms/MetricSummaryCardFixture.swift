//
// MetricSummaryCardFixture.swift
// LogYourBody
//
// Deterministic metric-card states for UI tests. Kept out of MetricSummaryCard
// so that file stays inside its recorded company size allowance.
//

import SwiftUI

// MARK: - Deterministic metric state fixture

#if DEBUG
/// Uses the production card and its native Button; handlers produce observable state/navigation.
struct MetricCardFixtureView: View {
    private let metrics = ["Steps", "Weight", "Body Fat", "FFMI"]
    @State private var order = DashboardViewLiquid.MetricIdentifier.allCases
    @State private var draggedMetric: DashboardViewLiquid.MetricIdentifier?
    @State private var dropTargetMetric: DashboardViewLiquid.MetricIdentifier?
    @State private var selectedState = "loading"
    @State private var completed: Set<String> = []
    @State private var invocations: [String: Int] = [:]
    @State private var detail: String?
    private let arguments = ProcessInfo.processInfo.arguments

    var body: some View {
        NavigationStack {
            ScrollView {
                DashboardMetricsList(
                    metricsOrder: $order, draggedMetric: $draggedMetric,
                    dropTargetMetric: $dropTargetMetric, onReorder: {},
                    cardContent: { metric in
                        metricCard(for: metric)
                    }
                )
                .padding(20)
            }
            .safeAreaInset(edge: .top) {
                VStack {
                    HStack {
                        stateButton("loading")
                        stateButton("empty")
                        stateButton("error")
                    }
                    HStack {
                        stateButton("permission")
                        stateButton("data")
                        stateButton("unavailable")
                    }
                    ForEach(metrics, id: \.self) { title in
                        Text("\(title) calls: \(invocations[title, default: 0])")
                            .font(.caption2)
                            .accessibilityIdentifier("metric_fixture_calls_\(title)")
                    }
                }
                .font(.caption)
                .padding(8)
                .background(Color.appBackground)
            }
            .navigationDestination(item: $detail) { title in
                Text("\(title) details")
                    .accessibilityIdentifier("metric_fixture_detail")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func metricCard(for metric: DashboardViewLiquid.MetricIdentifier) -> some View {
        let title = metric == .bodyFat ? "Body Fat" : metric == .ffmi ? "FFMI" : metric.rawValue.capitalized
        return MetricSummaryCard(
            icon: "chart.xyaxis.line", accentColor: Color.appPrimary,
            state: state(for: title), detailAction: detailAction(for: title)
        )
        .buttonStyle(MetricCardButtonStyle())
        .environment(\.metricCardIdentity, !arguments.contains("-lybUITestMetricCardLegacy"))
        .environment(\.metricCardActions, !arguments.contains("-lybUITestMetricCardLegacy"))
        .environment(\.dynamicTypeSize, arguments.contains("-lybUITestMetricCardAX3") ? .accessibility3 : .large)
        .accessibilityIdentifier("metric_fixture_\(title)")
    }

    private func stateButton(_ name: String) -> some View {
        Button(name.capitalized) {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedState = name
                completed = []
                invocations = [:]
            }
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("metric_fixture_state_\(name)")
    }

    private func state(for title: String) -> MetricSummaryCard.State {
        let actionTitle = selectedState == "error" ? "Retry"
            : selectedState == "permission" ? "Review Health access" : "Add measurement"
        let action = MetricSummaryCard.CardAction(
            title: actionTitle,
            hint: selectedState == "permission" ? "Shows Health access details" : nil
        ) {
            invocations[title, default: 0] += 1
            if selectedState == "permission" {
                detail = "\(title) Health access"
            } else {
                completed.insert(title)
            }
        }
        if completed.contains(title) || selectedState == "data" {
            let unit = title == "Steps" ? "steps" : title == "Weight" ? "kg" : title == "Body Fat" ? "%" : ""
            let value = title == "Steps" ? "8,000" : title == "Weight" ? "80" : title == "Body Fat" ? "18" : "20"
            let reading = Double(value.replacingOccurrences(of: ",", with: "")) ?? 0
            return .data(.init(
                title: title, value: value, unit: unit, timestamp: "October 25 at 08:00",
                dataPoints: [.init(index: 0, value: reading), .init(index: 1, value: reading)],
                chartAccessibilityLabel: "\(title) history, last 30 days",
                chartAccessibilityValue: "Latest value \(value) \(unit)",
                trend: .init(direction: .flat, valueText: "No change", caption: "1M"),
                footnote: title == "FFMI" ? "Calculated from weight, body fat and height" : "Source: Apple Health"
            ))
        }
        switch selectedState {
        case "empty":
            return .empty(title: title, message: "No measurements yet", action: action)
        case "error":
            return .error(title: title, message: "Unable to load measurements", action: action)
        case "permission":
            return .empty(title: title, message: "Health access needed", action: action)
        case "unavailable":
            return .error(title: title, message: "Measurements unavailable", action: nil)
        default:
            return .loading(title: title)
        }
    }

    private func detailAction(for title: String) -> MetricSummaryCard.CardAction? {
        guard selectedState != "unavailable" else { return nil }
        return .init(title: "Show \(title) details") {
            invocations[title, default: 0] += 1
            detail = title
        }
    }
}

#Preview("Metric state actions") {
    MetricCardFixtureView()
}
#endif
