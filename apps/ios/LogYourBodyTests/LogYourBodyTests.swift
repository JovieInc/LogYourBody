//
// LogYourBodyTests.swift
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

// Tests are split into focused files by surface area.

final class SupabaseURLBuilderTests: XCTestCase {
    func testBuildsRestStorageAndFunctionURLsFromValidBase() throws {
        let baseURL = "https://example.supabase.co"

        XCTAssertEqual(
            try SupabaseURLBuilder.restURL(
                table: "body_metrics",
                query: "user_id=eq.user-123",
                baseURL: baseURL
            ).absoluteString,
            "https://example.supabase.co/rest/v1/body_metrics?user_id=eq.user-123"
        )
        XCTAssertEqual(
            try SupabaseURLBuilder.storageURL(
                bucket: "photos",
                path: "user-123/photo.jpg",
                baseURL: baseURL
            ).absoluteString,
            "https://example.supabase.co/storage/v1/object/photos/user-123/photo.jpg"
        )
        XCTAssertEqual(
            try SupabaseURLBuilder.functionURL(
                "export-user-data",
                baseURL: baseURL
            ).absoluteString,
            "https://example.supabase.co/functions/v1/export-user-data"
        )
    }

    func testRejectsInvalidSupabaseBaseURL() {
        XCTAssertThrowsError(
            try SupabaseURLBuilder.restURL(
                table: "body_metrics",
                baseURL: "not a url"
            )
        ) { error in
            XCTAssertEqual(error as? SupabaseError, .invalidConfiguration)
        }
    }
}
