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
    var isLoading = false

    var id: ContextualMetricKind { kind }
    var isAvailable: Bool {
        !isLoading && !["", "–", "—", "-"].contains(value.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    var displayValue: String { isLoading ? "—" : value }

    var unavailableMessage: String? {
        guard !isAvailable else { return nil }
        return isLoading ? "Loading \(kind.title)…" : "\(kind.title) is unavailable for this date."
    }

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
            provenance: usesDerivedValue ? nil : metric.map { HomeV2Provenance.label(for: $0, field: .weight) },
            evidence: needsReview ? HomeV2WeightQuality.reviewMessage
                : ContextualMetricEvidencePolicy.label(for: .weight, isEstimated: usesDerivedValue, isSmoothed: usesDerivedValue)
        )
    }

    func detail(options: BodyScoreShareOptions) -> String {
        [evidence, options.includeObservation ? observation : nil,
         options.includeRange ? range : nil,
         options.includeTrend ? trend : nil,
         options.includeProvenance ? provenance : nil]
            .compactMap { $0 }.filter { ContextualMetricSharePolicy.hasDetail($0) }.joined(separator: " · ")
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

enum ContextualMetricDetailPolicy {
    /// Every interior correction changes the identity, including an estimate's evidence kind.
    static func fingerprint(points: [MetricChartDataPoint], trend: [MetricChartDataPoint]?) -> String {
        let raw = points.map(\.id).joined(separator: "|")
        let average = trend.map { $0.map(\.id).joined(separator: "|") } ?? "none"
        return "raw:\(points.count):\(raw);trend:\(average)"
    }

    static func validatedFocus(
        _ point: MetricChartDataPoint?, in series: [MetricChartDataPoint],
        currentFingerprint: String, cachedFingerprint: String
    ) -> MetricChartDataPoint? {
        guard currentFingerprint == cachedFingerprint, let point else { return nil }
        return series.first { $0.id == point.id }
    }

    static func source(
        point: MetricChartDataPoint?, entries: [MetricHistoryEntry], fallback: String?, isSmoothed: Bool
    ) -> String? {
        guard !isSmoothed else { return nil }
        return ContextualMetricSourcePolicy.source(for: point, entries: entries, fallback: fallback)
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
    static func hasDetail(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func canOfferScreenshot(isActive: Bool, isVisible: Bool, isPresenting: Bool) -> Bool {
        isActive && isVisible && !isPresenting
    }
}

extension BodyScoreSharePayload {
    static func contextual(
        _ snapshots: [ContextualMetricSnapshot], selected: ContextualMetricKind,
        includeUnavailableSelection: Bool = false
    ) -> Self? {
        // Home may retain its explicitly chosen unavailable metric. Never choose a replacement.
        let available = snapshots.filter {
            $0.isAvailable || (includeUnavailableSelection && $0.kind == selected)
        }
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

    /// A placeholder is an honest preview, never an exportable measurement.
    func canExport(options: BodyScoreShareOptions) -> Bool {
        guard options.selectedMetric != nil else {
            return contextualMetrics.isEmpty || score > 0
        }
        return snapshot(for: options)?.isAvailable == true
    }
}

/// A frozen offer/composer retains the account lifetime that produced its health data.
@MainActor
struct AccountBoundShareCapture {
    private(set) var payload: BodyScoreSharePayload?

    mutating func freeze(_ payload: BodyScoreSharePayload, owner: AuthManager.ProfileSessionOwnership) {
        self.payload = payload.owned(by: owner)
    }

    func authorizedPayload(owns: (AuthManager.ProfileSessionOwnership) -> Bool) -> BodyScoreSharePayload? {
        guard let payload, payload.isOwned(by: owns) else { return nil }
        return payload
    }

    mutating func reconcile(currentOwner: AuthManager.ProfileSessionOwnership?) {
        guard payload?.accountSession != currentOwner else { return }
        clear()
    }

    mutating func clear() { payload = nil }
}

/// Screenshot capture stays owned by iOS; an eligible screenshot opens the existing editor.
struct ContextualMetricShareModifier: ViewModifier {
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.scenePhase) private var scenePhase
    let payload: BodyScoreSharePayload?
    var isVisible = true
    @Binding var directRequest: Bool
    @State private var capture = AccountBoundShareCapture()
    private var pendingPayload: BodyScoreSharePayload? {
        capture.authorizedPayload(owns: authManager.ownsAccountSession)
    }
    @State private var contextOwner: AuthManager.ProfileSessionOwnership?
    @State private var isOnScreen = false
    @State private var showsComposer = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                contextOwner = authManager.captureAccountSession()
                isOnScreen = true
            }
            .onDisappear {
                isOnScreen = false
                invalidateShareContext()
            }
            .onChange(of: authManager.captureAccountSession()) { _, owner in
                invalidateShareContext(currentOwner: owner)
            }
            .onChange(of: isVisible) { _, visible in
                guard !visible else { return }
                capture.clear()
                showsComposer = false
                directRequest = false
            }
            .onScreenshot {
                guard let payload, let contextOwner, authManager.ownsAccountSession(contextOwner),
                      ContextualMetricSharePolicy.canOfferScreenshot(
                        isActive: scenePhase == .active,
                        isVisible: isVisible && isOnScreen,
                        isPresenting: showsComposer
                      ) else { return }
                capture.freeze(payload, owner: contextOwner)
                showsComposer = true
            }
            .onChange(of: directRequest) { _, requested in
                guard requested else { return }
                directRequest = false
                guard ContextualMetricSharePolicy.canOfferScreenshot(
                        isActive: scenePhase == .active,
                        isVisible: isVisible && isOnScreen,
                        isPresenting: showsComposer
                      ) else { return }
                guard let payload, let contextOwner,
                      authManager.ownsAccountSession(contextOwner) else {
                    invalidateShareContext()
                    return
                }
                capture.freeze(payload, owner: contextOwner)
                showsComposer = true
            }
            .sheet(isPresented: $showsComposer, onDismiss: { capture.clear() }, content: {
                if let pendingPayload, pendingPayload.isOwned(by: authManager.ownsAccountSession) {
                    BodyScoreShareSheet(payload: pendingPayload)
                }
            })
    }

    private func invalidateShareContext(currentOwner: AuthManager.ProfileSessionOwnership? = nil) {
        capture.reconcile(currentOwner: currentOwner)
        contextOwner = nil
        showsComposer = false
        directRequest = false
    }
}
