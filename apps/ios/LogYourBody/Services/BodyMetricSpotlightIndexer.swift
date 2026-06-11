//
// BodyMetricSpotlightIndexer.swift
// LogYourBody
//
import Foundation

#if canImport(CoreSpotlight)
import CoreSpotlight
import UniformTypeIdentifiers
#endif

struct BodyMetricSpotlightDocument: Equatable {
    static let domainIdentifier = "com.logyourbody.body-metrics"

    let identifier: String
    let title: String
    let contentDescription: String
    let keywords: [String]

    static func make(
        for metrics: BodyMetrics,
        preferredSystem: MeasurementSystem
    ) -> BodyMetricSpotlightDocument? {
        let parts = BodyMetricLoggingService.metricParts(
            for: metrics,
            preferredSystem: preferredSystem
        )

        guard !parts.isEmpty else {
            return nil
        }

        let title = "Latest LogYourBody metrics"
        let contentDescription = "\(parts.joined(separator: ", ")) on \(metrics.localDate)"
        var keywords = [
            "LogYourBody",
            "body metrics",
            "weight",
            "body composition",
            metrics.localDate
        ]

        if metrics.weight != nil {
            keywords.append("latest weight")
        }

        if metrics.bodyFatPercentage != nil {
            keywords.append("body fat")
        }

        return BodyMetricSpotlightDocument(
            identifier: "body-metric-\(metrics.id)",
            title: title,
            contentDescription: contentDescription,
            keywords: keywords
        )
    }
}

enum BodyMetricSpotlightIndexer {
    private static let logger = AppLogger(category: "spotlight")

    static func indexLatestMetric(
        _ metrics: BodyMetrics,
        preferredSystem: MeasurementSystem = .preferredFromDefaults
    ) {
        guard let document = BodyMetricSpotlightDocument.make(
            for: metrics,
            preferredSystem: preferredSystem
        ) else {
            return
        }

        #if canImport(CoreSpotlight)
        let attributeSet = CSSearchableItemAttributeSet(contentType: .data)
        attributeSet.title = document.title
        attributeSet.contentDescription = document.contentDescription
        attributeSet.keywords = document.keywords
        attributeSet.displayName = document.title

        let item = CSSearchableItem(
            uniqueIdentifier: document.identifier,
            domainIdentifier: BodyMetricSpotlightDocument.domainIdentifier,
            attributeSet: attributeSet
        )
        item.expirationDate = Calendar.current.date(byAdding: .year, value: 1, to: Date())

        CSSearchableIndex.default().indexSearchableItems([item]) { error in
            if let error {
                logger.error("Failed to index body metric in Spotlight: \(error.localizedDescription)")
            }
        }
        #endif
    }

    static func deleteAllIndexedMetrics() {
        #if canImport(CoreSpotlight)
        CSSearchableIndex.default().deleteSearchableItems(
            withDomainIdentifiers: [BodyMetricSpotlightDocument.domainIdentifier]
        ) { error in
            if let error {
                logger.error("Failed to clear body metric Spotlight index: \(error.localizedDescription)")
            }
        }
        #endif
    }
}
