import Foundation

struct BodyCompMeasurement: Identifiable, Equatable {
    let id: String
    let userId: String
    let timestamp: Date
    let weightRaw: Double?
    let weightUnit: String?
    let bodyFatRaw: Double?
    let bodyFatUnit: String?
    let method: BodyCompMethod
    let sourceType: BodyCompSourceType
    let source: String?
    let deviceId: String?
    let deviceNickname: String?
    let alignedBodyFat: Double?
    let alignmentVersion: Int?
    let contextFlags: [String]
    let notes: String?
    let photoUrl: String?
    let createdAt: Date
    let updatedAt: Date
}
