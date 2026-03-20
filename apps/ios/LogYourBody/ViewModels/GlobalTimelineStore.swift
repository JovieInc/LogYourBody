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
        update(
            bodyMetrics: metrics,
            dailyMetrics: [],
            bodyScoreContext: nil
        )
    }

    func update(
        bodyMetrics: [BodyMetrics],
        dailyMetrics: [DailyMetrics],
        bodyScoreContext: GlobalTimelineService.BodyScoreContext?
    ) {
        let input = GlobalTimelineService.BuildInput(
            bodyMetrics: bodyMetrics,
            dailyMetrics: dailyMetrics,
            bodyScoreContext: bodyScoreContext
        )

        weeklyBuckets = service.makeBuckets(for: .week, input: input)
        monthlyBuckets = service.makeBuckets(for: .month, input: input)
        yearlyBuckets = service.makeBuckets(for: .year, input: input)

        if cursor == nil {
            cursor = service.makeInitialCursor(for: input)
        } else if let currentCursor = cursor, bucket(for: currentCursor) == nil {
            cursor = service.makeInitialCursor(for: input)
        }
    }

    func bucket(for cursor: GlobalTimelineCursor) -> GlobalTimelineBucket? {
        buckets(for: cursor.scale).first { $0.id == cursor.bucketId }
    }

    func previousBucket(for cursor: GlobalTimelineCursor) -> GlobalTimelineBucket? {
        let bucketsAtScale = buckets(for: cursor.scale)
        guard let selectedIndex = bucketsAtScale.firstIndex(where: { $0.id == cursor.bucketId }),
              selectedIndex > 0 else {
            return nil
        }

        return bucketsAtScale[selectedIndex - 1]
    }

    func buckets(for scale: GlobalTimelineScale) -> [GlobalTimelineBucket] {
        switch scale {
        case .week:
            return weeklyBuckets
        case .month:
            return monthlyBuckets
        case .year:
            return yearlyBuckets
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
