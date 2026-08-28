//
// Changelog.swift
// LogYourBody
//
import Foundation

/// The installed binary evidence required before a review item may be shown.
/// This intentionally models customer-visible runtime provenance, not a PR,
/// commit, CI run, or deployment claim.
struct ReleaseReviewEvidence: Equatable {
    let product: String
    let version: String
    let build: String
    let destination: ReleaseReviewDestination

    func matches(version installedVersion: String, build installedBuild: String) -> Bool {
        version == installedVersion && build == installedBuild
    }
}

enum ReleaseReviewDestination: String, Equatable {
    case timeline = "logyourbody://timeline"

    var customerLabel: String {
        switch self {
        case .timeline:
            return "Timeline"
        }
    }
}

enum ReleaseReviewMetadataRole: Equatable {
    case label
    case value
}

/// A typed label/value pair prevents release evidence from collapsing into an
/// undifferentiated sentence in customer-facing UI.
struct ReleaseReviewMetadataField: Identifiable, Equatable {
    let id: String
    let label: String
    let value: String
    let labelRole: ReleaseReviewMetadataRole
    let valueRole: ReleaseReviewMetadataRole

    init(
        id: String,
        label: String,
        value: String,
        labelRole: ReleaseReviewMetadataRole = .label,
        valueRole: ReleaseReviewMetadataRole = .value
    ) {
        self.id = id
        self.label = label
        self.value = value
        self.labelRole = labelRole
        self.valueRole = valueRole
    }
}

struct ReleaseReviewItem: Identifiable, Equatable {
    let id: String
    let evidence: ReleaseReviewEvidence
    let title: String
    let summary: String
    let symbolName: String
    let actionTitle: String
    let adjacentActionDescription: String?

    init(
        id: String,
        evidence: ReleaseReviewEvidence,
        title: String,
        summary: String,
        symbolName: String,
        actionTitle: String,
        adjacentActionDescription: String? = nil
    ) {
        self.id = id
        self.evidence = evidence
        self.title = title
        self.summary = summary
        self.symbolName = symbolName
        self.actionTitle = actionTitle
        self.adjacentActionDescription = adjacentActionDescription
    }

    /// Stable across later builds so an already-reviewed change does not
    /// become new again merely because the binary was rebuilt.
    var reviewToken: String {
        "\(evidence.product):\(id)"
    }

    /// Exact installed-build identity retained separately from lifecycle state.
    var evidenceToken: String {
        "\(reviewToken)@\(evidence.version)+\(evidence.build)#\(evidence.destination.rawValue)"
    }
}

enum ReleaseReviewCatalog {
    static func metadata(for evidence: ReleaseReviewEvidence) -> [ReleaseReviewMetadataField] {
        [
            ReleaseReviewMetadataField(id: "version", label: "Version", value: evidence.version),
            ReleaseReviewMetadataField(id: "build", label: "Build", value: evidence.build)
        ]
    }

    /// Items compiled into this app line. The release evidence is taken from
    /// the installed bundle, so a surfaced item always names the exact binary
    /// the customer is using. Distribution remains a separate release proof.
    static func items(version: String, build: String) -> [ReleaseReviewItem] {
        [
            ReleaseReviewItem(
                id: "photo-timeline-review",
                evidence: ReleaseReviewEvidence(
                    product: "logyourbody",
                    version: version,
                    build: build,
                    destination: .timeline
                ),
                title: "Your progress, in one place",
                summary: "Review photos, weight, and body-fat context together on your timeline.",
                symbolName: "rectangle.stack",
                actionTitle: "Open timeline"
            )
        ]
    }
}

enum ReleaseReviewContentViolation: Equatable {
    case mergedMetadataSemantics(fieldID: String)
    case redundantAdjacentAction(itemID: String)
}

enum ReleaseReviewContentPolicy {
    static func violations(
        metadata: [ReleaseReviewMetadataField],
        items: [ReleaseReviewItem]
    ) -> [ReleaseReviewContentViolation] {
        let metadataViolations: [ReleaseReviewContentViolation] = metadata.compactMap { field in
            field.labelRole == field.valueRole
                ? .mergedMetadataSemantics(fieldID: field.id)
                : nil
        }
        let actionViolations: [ReleaseReviewContentViolation] = items.compactMap { item in
            hasRedundantAdjacentActionCopy(item)
                ? .redundantAdjacentAction(itemID: item.id)
                : nil
        }
        return metadataViolations + actionViolations
    }

    private static func hasRedundantAdjacentActionCopy(_ item: ReleaseReviewItem) -> Bool {
        guard let description = item.adjacentActionDescription else { return false }

        let normalizedDescription = normalize(description)
        let normalizedAction = normalize(item.actionTitle)
        let normalizedDestination = normalize(item.evidence.destination.customerLabel)
        let repeatsAction = normalizedDescription.contains(normalizedAction)
        let repeatsOpenDestination = normalizedDescription.contains("open \(normalizedDestination)")

        return repeatsAction || repeatsOpenDestination
    }

    private static func normalize(_ value: String) -> String {
        let words = value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .map { $0 == "opens" ? "open" : $0 }
        return words.joined(separator: " ")
    }
}

struct ReleaseReviewState: Equatable {
    var seenEvidenceTokens: Set<String> = []
    var reviewedTokens: Set<String> = []

    mutating func recordSeen(_ item: ReleaseReviewItem) {
        seenEvidenceTokens.insert(item.evidenceToken)
    }

    mutating func recordReviewed(_ item: ReleaseReviewItem) {
        recordSeen(item)
        reviewedTokens.insert(item.reviewToken)
    }

    func hasSeen(_ item: ReleaseReviewItem) -> Bool {
        seenEvidenceTokens.contains(item.evidenceToken)
    }

    func hasReviewed(_ item: ReleaseReviewItem) -> Bool {
        reviewedTokens.contains(item.reviewToken)
    }
}

final class ReleaseReviewStateStore {
    private enum Key {
        static let seen = "lyb.releaseReview.seenEvidenceTokens"
        static let reviewed = "lyb.releaseReview.reviewedTokens"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var state: ReleaseReviewState {
        ReleaseReviewState(
            seenEvidenceTokens: Set(defaults.stringArray(forKey: Key.seen) ?? []),
            reviewedTokens: Set(defaults.stringArray(forKey: Key.reviewed) ?? [])
        )
    }

    func recordSeen(_ item: ReleaseReviewItem) {
        var updatedState = state
        updatedState.recordSeen(item)
        persist(updatedState)
    }

    func recordReviewed(_ item: ReleaseReviewItem) {
        var updatedState = state
        updatedState.recordReviewed(item)
        persist(updatedState)
    }

    func reset() {
        defaults.removeObject(forKey: Key.seen)
        defaults.removeObject(forKey: Key.reviewed)
    }

    private func persist(_ state: ReleaseReviewState) {
        defaults.set(state.seenEvidenceTokens.sorted(), forKey: Key.seen)
        defaults.set(state.reviewedTokens.sorted(), forKey: Key.reviewed)
    }
}

enum ReleaseReviewPresentationPolicy {
    static func pendingItems(
        from items: [ReleaseReviewItem],
        installedVersion: String,
        installedBuild: String,
        reviewedTokens: Set<String>,
        isEligible: Bool
    ) -> [ReleaseReviewItem] {
        guard isEligible else { return [] }

        return items.filter { item in
            item.evidence.matches(version: installedVersion, build: installedBuild) &&
                !reviewedTokens.contains(item.reviewToken)
        }
    }
}
