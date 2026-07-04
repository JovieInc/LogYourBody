import Foundation

/// Background service that recalculates the latest body score when profile or
/// body metrics change. Heavy work runs off the main actor and results are
/// cached via `BodyScoreCache` for fast access on the dashboard hero.
final class BodyScoreRecalculationService {
    static let shared = BodyScoreRecalculationService()

    private let debounceInterval: TimeInterval
    private var lastScheduledAt: Date?
    private var pendingWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.logyourbody.bodyScore.recalculation", qos: .userInitiated)

    init(debounceInterval: TimeInterval = 0.4) {
        self.debounceInterval = debounceInterval
    }

    /// Schedule a background recalculation. Multiple calls in quick succession
    /// are coalesced to avoid redundant work.
    @discardableResult
    func scheduleRecalculation(now: Date = Date(), startTask: Bool = true) -> Bool {
        queue.sync { [weak self] in
            guard let self else { return false }

            if let last = self.lastScheduledAt,
               now >= last,
               now.timeIntervalSince(last) < self.debounceInterval {
                self.lastScheduledAt = now
                self.scheduleTrailingRecalculation(startTask: startTask)
                return false
            }

            self.lastScheduledAt = now
            self.pendingWorkItem?.cancel()
            self.startRecalculationIfNeeded(startTask: startTask)

            return true
        }
    }

    private func scheduleTrailingRecalculation(startTask: Bool) {
        pendingWorkItem?.cancel()
        guard startTask else { return }

        let workItem = DispatchWorkItem { [weak self] in
            self?.startRecalculationIfNeeded(startTask: true)
        }

        pendingWorkItem = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func startRecalculationIfNeeded(startTask: Bool) {
        guard startTask else { return }

        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.recalculateIfPossible()
        }
    }

    /// Perform a recalculation for the latest visible metrics, if we have
    /// enough information (sex, height, weight, body fat).
    func recalculateIfPossible() async {
        // Read user + profile on the main actor
        guard let user = await MainActor.run(body: { AuthManager.shared.currentUser }) else {
            return
        }

        guard let profile = user.profile else {
            return
        }

        // Determine biological sex from stored gender string
        let genderString = profile.gender?.lowercased() ?? ""
        let sex: BiologicalSex?
        if genderString.contains("female") || genderString.contains("woman") {
            sex = .female
        } else if genderString.contains("male") || genderString.contains("man") {
            sex = .male
        } else {
            sex = nil
        }

        guard let resolvedSex = sex else {
            return
        }

        guard let heightCm = profile.height, heightCm > 0 else {
            return
        }

        let heightValue = HeightValue(value: heightCm, unit: .centimeters)

        let birthYear: Int?
        if let dateOfBirth = profile.dateOfBirth {
            birthYear = Calendar.current.component(.year, from: dateOfBirth)
        } else {
            birthYear = nil
        }

        // Fetch latest visible body metrics for this user
        let metrics = await CoreDataManager.shared.fetchVisibleBodyMetrics(for: user.id)
        guard !metrics.isEmpty else {
            return
        }

        // Use the most recent entry that has both weight and body fat
        let sorted = metrics.sorted { $0.date > $1.date }
        guard let latest = sorted.first(where: { $0.weight != nil && $0.bodyFatPercentage != nil }) else {
            return
        }

        guard let weightKg = latest.weight, let bodyFat = latest.bodyFatPercentage else {
            return
        }

        // Resolve measurement preference from UserDefaults
        let measurementSystem = MeasurementSystem.preferredFromDefaults

        let weightValue = WeightValue(value: weightKg, unit: .kilograms)
        let bodyFatValue = BodyFatValue(percentage: bodyFat, source: .manualValue)
        let healthSnapshot = HealthImportSnapshot(
            heightCm: heightCm,
            weightKg: weightKg,
            bodyFatPercentage: bodyFat,
            birthYear: birthYear,
            heightDate: nil,
            weightDate: nil,
            bodyFatDate: nil
        )

        let input = BodyScoreInput(
            sex: resolvedSex,
            birthYear: birthYear,
            height: heightValue,
            weight: weightValue,
            bodyFat: bodyFatValue,
            measurementPreference: measurementSystem,
            healthSnapshot: healthSnapshot
        )

        guard input.isReadyForCalculation else {
            return
        }

        let context = BodyScoreCalculationContext(input: input, calculationDate: latest.date)
        let calculator = BodyScoreCalculator()

        do {
            let result = try calculator.calculateScore(context: context)
            BodyScoreCache.shared.store(result, for: user.id)

            await MainActor.run {
                NotificationCenter.default.post(name: .bodyScoreUpdated, object: nil)
            }
        } catch {
            // Intentionally swallow errors here; body score is non-critical.
        }
    }
}
