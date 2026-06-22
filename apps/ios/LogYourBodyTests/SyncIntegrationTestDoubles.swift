//
// SyncIntegrationTestDoubles.swift
// LogYourBodyTests
//
import XCTest
import AVFoundation
import CoreData
import HealthKit
import RevenueCat
import SwiftUI
import UIKit
@testable import LogYourBody

final class StubSupabaseManager: SupabaseManager {
    private(set) var bodyMetricsBatches: [[[String: Any]]] = []
    private(set) var dailyMetricsBatches: [[[String: Any]]] = []
    private(set) var profilePayloads: [[String: Any]] = []
    private(set) var dexaPayloads: [[String: Any]] = []
    private(set) var glp1DoseLogPayloads: [[String: Any]] = []
    private(set) var glp1MedicationPayloads: [[String: Any]] = []
    private(set) var endedActiveMedicationRequests: [(userId: String, endedAt: Date)] = []
    private(set) var deletedRecords: [(table: String, id: String)] = []

    override func upsertBodyMetricsBatch(_ metrics: [[String: Any]], token: String) async throws -> [[String: Any]] {
        bodyMetricsBatches.append(metrics)
        return metrics.compactMap { metric in
            guard let id = metric["id"] as? String else { return [:] }
            return ["id": id]
        }
    }

    override func upsertDailyMetricsBatch(_ metrics: [[String: Any]], token: String) async throws -> [[String: Any]] {
        dailyMetricsBatches.append(metrics)
        return metrics.compactMap { metric in
            guard let id = metric["id"] as? String else { return [:] }
            return ["id": id]
        }
    }

    override func updateProfile(_ profile: [String: Any], token: String) async throws {
        profilePayloads.append(profile)
    }

    override func upsertData(table: String, data: Data, token: String) async throws -> [[String: Any]] {
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        let array = jsonObject as? [[String: Any]] ?? []

        switch table {
        case "dexa_results":
            dexaPayloads.append(contentsOf: array)
        case "glp1_dose_logs":
            glp1DoseLogPayloads.append(contentsOf: array)
        case "glp1_medications":
            glp1MedicationPayloads.append(contentsOf: array)
        default:
            return []
        }

        return array.compactMap { payload in
            guard let id = payload["id"] as? String else { return nil }
            return ["id": id]
        }
    }

    override func deleteData(table: String, id: String, token: String) async throws {
        deletedRecords.append((table: table, id: id))
    }

    override func endActiveGlp1Medications(userId: String, endedAt: Date) async throws {
        endedActiveMedicationRequests.append((userId: userId, endedAt: endedAt))
    }
}

final class StubBodySpecDexaAPI: BodySpecDexaAPIClient {
    var pages: [Int: BodySpecResultsListResponse] = [:]
    var scanInfos: [String: BodySpecDexaScanInfoResponse] = [:]
    var compositions: [String: BodySpecDexaCompositionResponse] = [:]

    private(set) var compositionRequests: [String] = []

    func listResults(page: Int, pageSize: Int) async throws -> BodySpecResultsListResponse {
        pages[page] ?? BodySpecResultsListResponse(results: [])
    }

    func getDexaScanInfo(resultId: String) async throws -> BodySpecDexaScanInfoResponse {
        guard let scanInfo = scanInfos[resultId] else {
            throw BodySpecAPIError.invalidResponse
        }

        return scanInfo
    }

    func getDexaComposition(resultId: String) async throws -> BodySpecDexaCompositionResponse {
        compositionRequests.append(resultId)

        guard let composition = compositions[resultId] else {
            throw BodySpecAPIError.invalidResponse
        }

        return composition
    }
}
