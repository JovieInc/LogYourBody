import Foundation

enum DeviceConfidence: Double {
    case low = 0.3
    case medium = 0.6
    case high = 0.9
}

final class DeviceNormalizationService {
    static let shared = DeviceNormalizationService()

    private let coreDataManager = CoreDataManager.shared

    private init() {}

    func handleSample(_ sample: HKRawSample) async {
        guard let deviceId = canonicalDeviceId(for: sample) else { return }
        let method = inferMethod(for: sample)
        let confidence = confidenceForSample(sample, method: method)

        _ = await coreDataManager.upsertDevice(withId: deviceId) { device in
            device.manufacturer = sample.deviceManufacturer ?? sample.sourceName
            device.model = sample.deviceModel
            device.hardwareVersion = sample.deviceHardwareVersion
            device.firmwareVersion = sample.deviceFirmwareVersion
            device.softwareVersion = sample.deviceSoftwareVersion
            device.sourceBundleId = sample.sourceBundleId
            device.deviceManufacturer = sample.deviceManufacturer
            device.deviceModel = sample.deviceModel
            device.deviceHardwareVersion = sample.deviceHardwareVersion
            device.deviceFirmwareVersion = sample.deviceFirmwareVersion
            device.deviceSoftwareVersion = sample.deviceSoftwareVersion
            device.deviceLocalIdentifier = sample.deviceLocalIdentifier
            device.deviceUDI = sample.deviceUDI
            device.inferredMethod = method.rawValue
            device.confidence = confidence.rawValue
        }

        let userDeviceId = userDeviceKey(userId: sample.userId, deviceId: deviceId)
        _ = await coreDataManager.upsertUserDevice(withId: userDeviceId) { userDevice in
            userDevice.userId = sample.userId
            userDevice.deviceId = deviceId
            if userDevice.firstSeenAt == nil {
                userDevice.firstSeenAt = sample.startDate
            }
            userDevice.lastSeenAt = sample.endDate
            userDevice.inferredMethod = method.rawValue
        }
    }

    private func canonicalDeviceId(for sample: HKRawSample) -> String? {
        if let bundleId = sample.sourceBundleId, !bundleId.isEmpty {
            return bundleId
        }
        if let localId = sample.deviceLocalIdentifier, !localId.isEmpty {
            return localId
        }
        if let manufacturer = sample.deviceManufacturer, let model = sample.deviceModel {
            return "\(manufacturer.lowercased())_\(model.lowercased())"
        }
        if let sourceName = sample.sourceName {
            return sourceName.lowercased().replacingOccurrences(of: " ", with: "_")
        }
        return sample.hkUUID
    }

    private func userDeviceKey(userId: String, deviceId: String) -> String {
        return "\(userId)-\(deviceId)"
    }

    private func inferMethod(for sample: HKRawSample) -> BodyCompMethod {
        if let bundleId = sample.sourceBundleId?.lowercased() {
            if bundleId.contains("dexa") {
                return .dexa
            }
            if bundleId.contains("scan") && bundleId.contains("body") {
                return .biaScale
            }
            if bundleId.contains("caliper") {
                return .caliper
            }
        }

        if let manufacturer = sample.deviceManufacturer?.lowercased() {
            if manufacturer.contains("tanita") || manufacturer.contains("withings") || manufacturer.contains("renpho") {
                return .biaScale
            }
        }

        if sample.quantityType.contains("dexa") {
            return .dexa
        }

        return .biaScale
    }

    private func confidenceForSample(_ sample: HKRawSample, method: BodyCompMethod) -> DeviceConfidence {
        if method == .dexa {
            return .high
        }
        if let manufacturer = sample.deviceManufacturer?.lowercased(),
           manufacturer.contains("tanita") || manufacturer.contains("withings") {
            return .medium
        }
        return .low
    }
}
