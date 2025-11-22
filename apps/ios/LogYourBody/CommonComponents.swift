//
// CommonComponents.swift
// LogYourBody
//
// Re-exports all common UI components and shared UI models
import SwiftUI
import Foundation

// MARK: - Shared Metric Entry Models

struct MetricEntry: Identifiable, Equatable {
    let id: String
    let date: Date
    let primaryValue: Double
    let primaryUnit: String
    let secondaryValue: Double?
    let secondaryUnit: String?
    let notes: String?
    let source: EntrySource
    let isEditable: Bool
    let isHidden: Bool
}

enum EntrySource: Equatable {
    case manual
    case healthKit
    case integration(name: String?)

    struct Configuration {
        let icon: String
        let iconColor: Color
        let background: Color
    }

    var configuration: Configuration {
        switch self {
        case .manual:
            return Configuration(
                icon: "pencil",
                iconColor: .white,
                background: Color.white.opacity(0.15)
            )
        case .healthKit:
            return Configuration(
                icon: "heart.fill",
                iconColor: .red,
                background: Color.red.opacity(0.2)
            )
        case .integration:
            return Configuration(
                icon: "bolt.horizontal",
                iconColor: .blue,
                background: Color.blue.opacity(0.2)
            )
        }
    }

    var labelText: String {
        switch self {
        case .manual:
            return "Manual"
        case .healthKit:
            return "Health"
        case .integration(let name):
            return name ?? "Integration"
        }
    }
}

// Common components are imported directly from their respective files
// No need for typealiases as Swift doesn't use namespaces like this
