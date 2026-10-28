/// Plain input is an action so ranking can never remove keyboard/VoiceOver entry.
enum QuickPill: String, CaseIterable {
    case addPhoto
    case weight
    case bodyFat
    case plainInput
}

/// Pure ordering only. The caller owns data access, freshness windows and rollout.
enum QuickPillRanker {
    struct Context: Equatable {
        let weight: SignalFreshness
        let bodyFat: SignalFreshness
        let photo: SignalFreshness

        init(
            weight: SignalFreshness = .missing,
            bodyFat: SignalFreshness = .missing,
            photo: SignalFreshness = .missing
        ) {
            self.weight = weight
            self.bodyFat = bodyFat
            self.photo = photo
        }
    }

    /// Missing/stale signals lead in a stable order: photo, weight, body fat.
    /// Fresh weight is omitted; other satisfied signals remain after plain input.
    static func rank(_ context: Context) -> [QuickPill] {
        let signals: [(pill: QuickPill, freshness: SignalFreshness)] = [
            (.addPhoto, context.photo),
            (.weight, context.weight),
            (.bodyFat, context.bodyFat)
        ]
        let useful = signals.filter { $0.freshness != .fresh }.map(\.pill)
        let satisfied = signals.filter { $0.freshness == .fresh && $0.pill != .weight }.map(\.pill)
        return useful + [.plainInput] + satisfied
    }
}
