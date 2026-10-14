import SwiftUI
import UIKit

/// A frozen copy of the selected screen, never a request for unrelated history.
enum ContextualMetricKind: String, CaseIterable, Identifiable {
    case steps, weight, bodyFat, ffmi, bodyScore

    var id: String { rawValue }
    var title: String {
        switch self {
        case .steps: return "Steps"
        case .weight: return "Weight"
        case .bodyFat: return "Body fat"
        case .ffmi: return "FFMI"
        case .bodyScore: return "Body Score"
        }
    }

    static func from(title: String) -> Self? {
        switch title.lowercased() {
        case "steps": return .steps
        case "weight": return .weight
        case "body fat", "body fat %": return .bodyFat
        case "ffmi": return .ffmi
        case "body score": return .bodyScore
        default: return nil
        }
    }
}

struct ContextualMetricSnapshot: Equatable, Identifiable {
    let kind: ContextualMetricKind
    let value: String
    let unit: String
    let observation: String
    let range: String
    let trend: String?
    let provenance: String?
    var evidence: String?

    var id: ContextualMetricKind { kind }
    var isAvailable: Bool { !["", "–", "—", "-"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines)) }

    static func steps(_ daily: DailyMetrics?, value: String, range: String) -> Self {
        Self(kind: .steps, value: value, unit: "steps",
             observation: daily?.date.formatted(date: .abbreviated, time: .omitted) ?? "",
             range: range, trend: nil, provenance: daily == nil ? nil : "Apple Health")
    }

    /// Match the canonical measured-first headline, including its raw flagged fallback.
    static func weight(
        _ metric: BodyMetrics?, metrics: [BodyMetrics], prefersTrend: Bool,
        context: (unit: String, observation: String, range: String), formatValue: (Double) -> String
    ) -> Self {
        let derived = metric.flatMap { HomeV2WeightQuality.trendWeight(for: $0, in: metrics) }
        let kilograms = TimelineWeightHeadlinePolicy.kilograms(
            measuredWeight: metric?.weight, trendWeight: derived, prefersTrend: prefersTrend
        ).flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let usesDerivedValue = metric?.weight == nil && kilograms != nil
        let needsReview = metric?.weight != nil && !HomeV2WeightQuality.isWithinSupportedLoggingRange(metric?.weight)
        return Self(
            kind: .weight, value: kilograms.map(formatValue) ?? "—", unit: context.unit,
            observation: context.observation, range: context.range, trend: nil,
            provenance: usesDerivedValue ? nil : metric.map { HomeV2Provenance.label(for: $0) },
            evidence: needsReview ? HomeV2WeightQuality.reviewMessage
                : ContextualMetricEvidencePolicy.label(for: .weight, isEstimated: usesDerivedValue, isSmoothed: usesDerivedValue)
        )
    }

    func detail(options: BodyScoreShareOptions) -> String {
        [evidence, options.includeObservation ? observation : nil,
         options.includeRange ? range : nil,
         options.includeTrend ? trend : nil,
         options.includeProvenance ? provenance : nil]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

enum ContextualMetricProgressPolicy {
    struct Selection {
        let point: MetricChartDataPoint
        let isSmoothed: Bool
        var isFocused = false

        func source(entries: [MetricHistoryEntry]) -> String? {
            isSmoothed ? nil : ContextualMetricSourcePolicy.source(for: point, entries: entries, fallback: nil)
        }
    }

    /// A removed, refreshed or hidden chart focus cannot outlive the current data.
    static func presentationSelection(
        points: [MetricChartDataPoint], averages: [MetricChartDataPoint],
        focus: HomeV2ChartIntegrity.Sample?
    ) -> Selection? {
        let observed = HomeV2MetricEditorial.observedPoints(points)
        if HomeV2TrendPolicy.hasEnoughData(observed), let focus,
           let selected = selection(points: observed, averages: averages, focus: focus) {
            return selected
        }
        return selection(points: observed, focus: nil)
    }

    static func selection(
        points: [MetricChartDataPoint], averages: [MetricChartDataPoint] = [],
        focus: HomeV2ChartIntegrity.Sample?
    ) -> Selection? {
        if let focus {
            let candidates = focus.kind == .daily ? points : averages
            guard let point = candidates.first(where: {
                $0.date == focus.date && abs($0.value - focus.value) < 0.0001
            }) else { return nil }
            return Selection(point: point, isSmoothed: focus.kind == .sevenDayAverage, isFocused: true)
        }
        return HomeV2MetricEditorial.observedPoints(points).max { $0.date < $1.date }
            .map { Selection(point: $0, isSmoothed: false) }
    }
}

enum ContextualMetricEvidencePolicy {
    static func label(for kind: ContextualMetricKind, isEstimated: Bool = false,
                      bodyFatMethod: String? = nil, isSmoothed: Bool = false) -> String? {
        switch kind {
        case .ffmi, .bodyScore: return "Derived estimate"
        case .bodyFat: return isEstimated || bodyFatMethod == "visual_estimate" ? "Estimated" : nil
        case .weight: return isSmoothed ? "Smoothed" : (isEstimated ? "Estimated" : nil)
        case .steps: return isEstimated ? "Estimated" : nil
        }
    }
}

enum ContextualMetricSourcePolicy {
    /// A historical focus must not borrow the latest measurement's source.
    static func source(for point: MetricChartDataPoint?, entries: [MetricHistoryEntry], fallback: String?) -> String? {
        guard let point else { return fallback }
        let matches = entries.filter { $0.date == point.date && abs($0.primaryValue - point.value) < 0.0001 }
        let sources = Set(matches.map { entry -> String in
            switch entry.source {
            case .manual: return "Manual"
            case .healthKit: return "Apple Health"
            case .integration(let id): return id ?? "Connected"
            }
        })
        let known = sources.count == 1 ? sources.first : nil
        return known
    }
}

enum ContextualMetricSharePolicy {
    static func canOfferScreenshot(isActive: Bool, isVisible: Bool, isPresenting: Bool) -> Bool {
        isActive && isVisible && !isPresenting
    }
}

extension BodyScoreSharePayload {
    static func contextual(_ snapshots: [ContextualMetricSnapshot], selected: ContextualMetricKind) -> Self? {
        let available = snapshots.filter(\.isAvailable)
        guard available.contains(where: { $0.kind == selected }) else { return nil }
        return Self(
            score: 0, scoreText: "", tagline: "", ffmiValue: "", ffmiCaption: "",
            bodyFatValue: "", bodyFatCaption: "", weightValue: "", weightCaption: "",
            deltaText: nil, bodyFatPercentage: nil, gender: nil, photoImage: nil,
            contextualMetrics: available, preferredMetric: selected
        )
    }

    func snapshot(for options: BodyScoreShareOptions) -> ContextualMetricSnapshot? {
        contextualMetrics.first { $0.kind == options.selectedMetric }
    }
}

/// Screenshot capture remains entirely owned by iOS. Only an explicit acceptance opens the composer.
struct ContextualMetricShareModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let payload: BodyScoreSharePayload?
    var isVisible = true
    @Binding var directRequest: Bool
    @State private var pendingPayload: BodyScoreSharePayload?
    @State private var isOnScreen = false
    @State private var showsOffer = false
    @State private var showsComposer = false

    func body(content: Content) -> some View {
        content
            .onAppear { isOnScreen = true }
            .onDisappear { isOnScreen = false }
            .onScreenshot {
                guard payload != nil,
                      ContextualMetricSharePolicy.canOfferScreenshot(
                        isActive: scenePhase == .active,
                        isVisible: isVisible && isOnScreen,
                        isPresenting: showsOffer || showsComposer
                      ) else { return }
                pendingPayload = payload
                showsOffer = true
            }
            .confirmationDialog("Create a share card?", isPresented: $showsOffer, titleVisibility: .visible) {
                Button("Share \(pendingPayload?.preferredMetric?.title ?? "metric")") { showsComposer = true }
                Button("Not now", role: .cancel) { pendingPayload = nil }
            } message: {
                Text("Your screenshot stays unchanged. Choose the details to include before sharing.")
            }
            .onChange(of: directRequest) { _, requested in
                guard requested else { return }
                directRequest = false
                pendingPayload = payload
                showsComposer = payload != nil
            }
            .sheet(isPresented: $showsComposer, onDismiss: { pendingPayload = nil }, content: {
                if let pendingPayload { BodyScoreShareSheet(payload: pendingPayload) }
            })
    }
}
