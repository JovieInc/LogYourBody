//
// BodyMetricSourceMetadata+WeeklyPhoto.swift
// LogYourBody
//
import Foundation

extension BodyMetricSourceMetadata {
    var weeklyPhotoProvenance: WeeklyPhotoProvenance? {
        guard let fields = extraFields[WeeklyPhotoProvenance.storageKey]?.object else { return nil }
        return WeeklyPhotoProvenance(storage: fields.compactMapValues(\.string))
    }

    func recordingWeeklyPhoto(_ provenance: WeeklyPhotoProvenance) -> Self {
        var updated = self
        updated.extraFields[WeeklyPhotoProvenance.storageKey] = .objectValue(
            provenance.storageFields.mapValues { .text($0) }
        )
        return updated
    }
}
