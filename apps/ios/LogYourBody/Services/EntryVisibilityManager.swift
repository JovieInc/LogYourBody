import Foundation

final class EntryVisibilityManager {
    static let shared = EntryVisibilityManager()

    private let defaults = UserDefaults.standard
    private let storageKey = "hiddenMetricEntries"

    private init() {}

    private func key(for userId: String) -> String {
        "\(storageKey)_\(userId)"
    }

    func hiddenIds(for userId: String) -> Set<String> {
        guard !userId.isEmpty,
              let stored = defaults.array(forKey: key(for: userId)) as? [String] else {
            return []
        }
        return Set(stored)
    }

    func isHidden(entryId: String, userId: String) -> Bool {
        hiddenIds(for: userId).contains(entryId)
    }

    func hide(entryId: String, userId: String) {
        updateHiddenState(true, entryId: entryId, userId: userId)
    }

    func unhide(entryId: String, userId: String) {
        updateHiddenState(false, entryId: entryId, userId: userId)
    }

    func filterVisibleMetrics(_ metrics: [BodyMetrics], userId: String) -> [BodyMetrics] {
        let hidden = hiddenIds(for: userId)
        guard !hidden.isEmpty else { return metrics }
        return metrics.filter { !hidden.contains($0.id) }
    }

    func segregateMetrics(_ metrics: [BodyMetrics], userId: String) -> (visible: [BodyMetrics], hidden: [BodyMetrics]) {
        let hiddenIds = hiddenIds(for: userId)
        guard !hiddenIds.isEmpty else {
            return (metrics, [])
        }

        let (hidden, visible) = metrics.reduce(into: ([BodyMetrics](), [BodyMetrics]())) { result, metric in
            if hiddenIds.contains(metric.id) {
                result.0.append(metric)
            } else {
                result.1.append(metric)
            }
        }

        return (
            visible.sorted { $0.date > $1.date },
            hidden.sorted { $0.date > $1.date }
        )
    }

    func prepareMetricsForDisplay(_ metrics: [BodyMetrics], userId: String) -> (visible: [BodyMetrics], hidden: [BodyMetrics]) {
        let segregated = segregateMetrics(metrics, userId: userId)
        return (
            resolveConflicts(segregated.visible),
            segregated.hidden
        )
    }

    func resolvedVisibleMetrics(_ metrics: [BodyMetrics], userId: String) -> [BodyMetrics] {
        resolveConflicts(filterVisibleMetrics(metrics, userId: userId))
    }

    private func updateHiddenState(_ hidden: Bool, entryId: String, userId: String) {
        guard !userId.isEmpty else { return }
        var ids = hiddenIds(for: userId)
        if hidden {
            ids.insert(entryId)
        } else {
            ids.remove(entryId)
        }
        defaults.set(Array(ids), forKey: key(for: userId))
    }

    private func resolveConflicts(_ metrics: [BodyMetrics]) -> [BodyMetrics] {
        guard !metrics.isEmpty else { return [] }

        let calendar = Calendar.current
        var merged: [String: BodyMetrics] = [:]

        for metric in metrics.sorted(by: { $0.date > $1.date }) {
            let key = slotKey(for: metric.date, calendar: calendar)

            if let existing = merged[key] {
                if shouldReplace(existing: existing, with: metric) {
                    merged[key] = metric
                }
            } else {
                merged[key] = metric
            }
        }

        return merged.values.sorted { $0.date > $1.date }
    }

    private func slotKey(for date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        let hour = components.hour ?? 0
        return "\(year)-\(month)-\(day)-\(hour)"
    }

    private func shouldReplace(existing: BodyMetrics, with candidate: BodyMetrics) -> Bool {
        let existingPriority = sourcePriority(for: existing)
        let candidatePriority = sourcePriority(for: candidate)

        if candidatePriority != existingPriority {
            return candidatePriority > existingPriority
        }

        return candidate.updatedAt > existing.updatedAt
    }

    private func sourcePriority(for metric: BodyMetrics) -> Int {
        let normalized = (metric.dataSource ?? "manual").lowercased()

        if normalized.contains("manual") || normalized.isEmpty {
            return 3
        }

        if normalized.contains("health") {
            return 1
        }

        return 2 // Other integrations
    }
}
