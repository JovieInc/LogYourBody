import Foundation

enum PersonalBodyViewKind: String, Codable, Equatable {
    case front
    case side
    case back
    case diary
}

enum PersonalBodyCaptureQuality: String, Codable, Equatable {
    case supported
    case poor
    case occluded
    case poseChanged
    case missing
}

enum PersonalBodyRoute: String, Codable, Equatable {
    case onDevice = "on-device"
    case external
}

struct PersonalBodyCapture: Codable, Equatable {
    var id: String
    var accountId: String
    var photoId: String
    var sessionId: String?
    var view: PersonalBodyViewKind
    var effectiveDate: String
    var quality: PersonalBodyCaptureQuality
    var torsoWidth: Double?
    var torsoDepth: Double?
    var dexaBodyFat: Double?
    var dexaDate: String?
}

struct PersonalBodyIdentity: Codable, Equatable {
    var accountId: String
    var bodyId: String
    var frame: Double
}

struct PersonalBodyShape: Codable, Equatable {
    var adiposity: Double
    var muscularity: Double
    var frame: Double
    var depth: Double
}

struct PersonalBodySnapshot: Codable, Equatable {
    var schema: String
    var id: String
    var accountId: String
    var bodyId: String
    var frame: Double
    var modelId: String
    var modelVersion: String
    var topologyId: String
    var rigId: String
    var effectiveDate: String
    var sessionId: String?
    var shape: PersonalBodyShape
    var supported: [String]
    var inferred: [String]
    var evidence: String
    var photoIds: [String]
    var captureIds: [String]
    var claimsBodyFat: Bool
    var claimsWeeklyChange: Bool
}

struct PersonalBodyDiary: Codable, Equatable {
    var accountId: String
    var photoId: String
    var effectiveDate: String
    var reason: String
}

struct PersonalBodyJob: Codable, Equatable {
    var id: String
    var accountId: String
    var status: String
    var attempts: Int
    var snapshotId: String?
    var failure: String?
}

struct PersonalBodyArchive: Codable, Equatable {
    var accountId: String
    var captures: [PersonalBodyCapture]
    var diaries: [PersonalBodyDiary]
    var snapshots: [PersonalBodySnapshot]
    var jobs: [PersonalBodyJob]

    static func empty(_ accountId: String) -> PersonalBodyArchive {
        PersonalBodyArchive(accountId: accountId, captures: [], diaries: [], snapshots: [], jobs: [])
    }
}

struct PersonalBodyFitRequest: Equatable {
    var now: Int
    var deadline: Int
    var online: Bool
    var route: PersonalBodyRoute
    var consentGranted: Bool
    var providerAvailable: Bool
    var canceled: Bool
    var identity: PersonalBodyIdentity
    var captures: [PersonalBodyCapture]
    var prior: PersonalBodyShape?
    var activeTopology: String
}

struct PersonalBodyJobReceipt: Equatable {
    var job: PersonalBodyJob
    var snapshot: PersonalBodySnapshot?
    var diaries: [PersonalBodyDiary]
    var journey: String
}

struct PersonalBodyDisplay: Codable, Equatable {
    var kind: String
    var shape: PersonalBodyShape?
    var topologyId: String?
    var isolated: Bool
    var label: String
    var claimsBodyFat: Bool
    var claimsWeeklyChange: Bool
}

struct PersonalBodyIndex: Equatable {
    var displays: [String: PersonalBodyDisplay]
    static let empty = PersonalBodyIndex(displays: [:])
}

struct PersonalBodyViewpoint: Equatable {
    var yaw: Double
    var scale: Double
}

enum PersonalBodyDay {
    static func key(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
