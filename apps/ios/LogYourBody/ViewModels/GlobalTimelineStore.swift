import Foundation
import SwiftUI

@MainActor
final class GlobalTimelineStore: ObservableObject {
    @Published private(set) var cursor: GlobalTimelineCursor?
    @Published private(set) var weeklyBuckets: [GlobalTimelineBucket] = []
    @Published private(set) var monthlyBuckets: [GlobalTimelineBucket] = []
    @Published private(set) var yearlyBuckets: [GlobalTimelineBucket] = []

    private let service: GlobalTimelineService

    init(service: GlobalTimelineService = GlobalTimelineService()) {
        self.service = service
    }

    // MARK: - Public API

    func updateMetrics(_ metrics: [BodyMetrics]) {
        weeklyBuckets = service.makeBuckets(for: .week, metrics: metrics)
        monthlyBuckets = service.makeBuckets(for: .month, metrics: metrics)
        yearlyBuckets = service.makeBuckets(for: .year, metrics: metrics)

        if cursor == nil {
            cursor = service.makeInitialCursor(for: metrics)
        } else if let currentCursor = cursor, bucket(for: currentCursor) == nil {
            cursor = service.makeInitialCursor(for: metrics)
        }
    }

    func bucket(for cursor: GlobalTimelineCursor) -> GlobalTimelineBucket? {
        switch cursor.scale {
        case .week:
            return weeklyBuckets.first { $0.id == cursor.bucketId }
        case .month:
            return monthlyBuckets.first { $0.id == cursor.bucketId }
        case .year:
            return yearlyBuckets.first { $0.id == cursor.bucketId }
        }
    }

    func updateCursor(_ newCursor: GlobalTimelineCursor) {
        guard newCursor != cursor else { return }
        cursor = newCursor
    }

    func selectToday() {
        guard let latestWeek = weeklyBuckets.last else { return }
        cursor = GlobalTimelineCursor(
            date: latestWeek.endDate,
            scale: .week,
            bucketId: latestWeek.id
        )
    }
}
