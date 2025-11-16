import Foundation

struct HKRawSample: Identifiable, Equatable {
    let id: String
    let userId: String
    let hkUUID: String
    let quantityType: String
    let value: Double
    let unit: String
    let startDate: Date
    let endDate: Date
    let sourceName: String?
    let sourceBundleId: String?
    let deviceManufacturer: String?
    let deviceModel: String?
    let deviceHardwareVersion: String?
    let deviceFirmwareVersion: String?
    let deviceSoftwareVersion: String?
    let deviceLocalIdentifier: String?
    let deviceUDI: String?
    let metadata: [String: String]?
    let createdAt: Date
    let updatedAt: Date
}
