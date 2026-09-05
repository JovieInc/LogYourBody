import Foundation
import SwiftUI

@MainActor
final class GlobalTimelineStore: ObservableObject {
    @Published private(set) var cursor: GlobalTimelineCursor?
    @Published private(set) var weeklyBuckets: [GlobalTimelineBucket] = []
    @Published private(set) var monthlyBuckets: [GlobalTimelineBucket] = []
    @Published private(set) var yearlyBuckets: [GlobalTimelineBucket] = []

    typealias BucketBuilder = (GlobalTimelineScale, [BodyMetrics], [DailyMetrics], Double?) -> [GlobalTimelineBucket]

    private let buildBuckets: BucketBuilder
    private var contentSignature: ContentSignature?

    private struct ContentSignature: Equatable {
        let metrics: [BodyMetrics]
        let dailyMetrics: [DailySignature]
        let heightInches: Double?
        let interpolationCalendar: Calendar
    }

    private struct DailySignature: Equatable {
        let id: String
        let userId: String
        let date: Date
        let steps: Int?

        init(_ metric: DailyMetrics) {
            id = metric.id
            userId = metric.userId
            date = metric.date
            steps = metric.steps
        }
    }

    init(service: GlobalTimelineService = GlobalTimelineService(), bucketBuilder: BucketBuilder? = nil) {
        self.buildBuckets = bucketBuilder ?? { scale, metrics, dailyMetrics, heightInches in
            service.makeBuckets(for: scale, metrics: metrics, dailyMetrics: dailyMetrics, heightInches: heightInches)
        }
    }

    // MARK: - Public API

    func updateMetrics(
        _ metrics: [BodyMetrics],
        dailyMetrics: [DailyMetrics] = [],
        heightInches: Double? = nil
    ) {
        // Compare values, not just IDs or timestamps: imports can correct an
        // existing measurement without changing either. Selection is not content.
        let signature = ContentSignature(
            metrics: metrics,
            dailyMetrics: dailyMetrics.map(DailySignature.init),
            heightInches: heightInches,
            interpolationCalendar: .current
        )
        if signature != contentSignature {
            contentSignature = signature
            weeklyBuckets = buildBuckets(.week, metrics, dailyMetrics, heightInches)
            monthlyBuckets = buildBuckets(.month, metrics, dailyMetrics, heightInches)
            yearlyBuckets = buildBuckets(.year, metrics, dailyMetrics, heightInches)
        }

        if cursor.flatMap({ bucket(for: $0) }) == nil {
            // The weekly buckets already contain everything needed for the
            // initial cursor; avoid constructing the same scale a fourth time.
            cursor = weeklyBuckets.last.map {
                GlobalTimelineCursor(date: $0.endDate, scale: .week, bucketId: $0.id)
            }
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
