//
//  AvatarBodyRenderer.swift
//  LogYourBody
//
//  Renders wireframe body silhouettes based on body fat percentage
//

import SwiftUI

/// Renders a white wireframe body silhouette on black background based on BF%
struct AvatarBodyRenderer: View {
    let bodyFatPercentage: Double?
    let gender: String?
    let height: CGFloat

    var body: some View {
        ZStack {
            // Black background
            Color.black

            // Wireframe body
            if let bodyFat = bodyFatPercentage {
                WireframeBody(bodyFatPercentage: bodyFat, gender: gender ?? "male")
                    .stroke(Color.white, lineWidth: 2)
                    .frame(height: height)
            } else {
                // No BF% data - show placeholder
                VStack(spacing: 12) {
                    Image(systemName: "figure.stand")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.3))
                    Text("No body composition data")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .frame(height: height)
        .cornerRadius(12)
    }
}

/// Custom shape for wireframe body based on BF%
struct WireframeBody: Shape {
    let bodyFatPercentage: Double
    let gender: String

    func path(in rect: CGRect) -> Path {
        let isMale = gender.lowercased() == "male"

        // Determine body proportions based on BF%
        let bodyType = classifyBodyType(bodyFat: bodyFatPercentage, isMale: isMale)

        var path = Path()
        let centerX = rect.midX
        let width = rect.width * 0.6 // Body takes up 60% of width

        // Scale factors based on body fat
        let (shoulderWidth, waistWidth, hipWidth, neckWidth) = bodyType.dimensions

        // Calculate positions (from top to bottom)
        let headTop = rect.minY + rect.height * 0.05
        let headHeight = rect.height * 0.15
        let neckTop = headTop + headHeight
        let neckHeight = rect.height * 0.05
        let shoulderTop = neckTop + neckHeight
        let chestMid = shoulderTop + rect.height * 0.15
        let waistTop = shoulderTop + rect.height * 0.30
        let hipTop = waistTop + rect.height * 0.10
        let bottom = rect.maxY - rect.height * 0.05

        // Head (circle)
        let headRadius = width * 0.12
        path.addEllipse(in: CGRect(
            x: centerX - headRadius,
            y: headTop,
            width: headRadius * 2,
            height: headHeight
        ))

        // Neck
        let neckX = width * neckWidth / 2
        path.move(to: CGPoint(x: centerX - neckX, y: neckTop))
        path.addLine(to: CGPoint(x: centerX - neckX, y: shoulderTop))
        path.move(to: CGPoint(x: centerX + neckX, y: neckTop))
        path.addLine(to: CGPoint(x: centerX + neckX, y: shoulderTop))

        // Shoulders to waist (torso outline)
        let shoulderX = width * shoulderWidth / 2
        let waistX = width * waistWidth / 2

        // Left side of torso
        path.move(to: CGPoint(x: centerX - shoulderX, y: shoulderTop))
        path.addCurve(
            to: CGPoint(x: centerX - waistX, y: waistTop),
            control1: CGPoint(x: centerX - shoulderX, y: chestMid),
            control2: CGPoint(x: centerX - waistX, y: chestMid)
        )

        // Right side of torso
        path.move(to: CGPoint(x: centerX + shoulderX, y: shoulderTop))
        path.addCurve(
            to: CGPoint(x: centerX + waistX, y: waistTop),
            control1: CGPoint(x: centerX + shoulderX, y: chestMid),
            control2: CGPoint(x: centerX + waistX, y: chestMid)
        )

        // Waist to hips
        let hipX = width * hipWidth / 2

        // Left waist to hip
        path.move(to: CGPoint(x: centerX - waistX, y: waistTop))
        path.addLine(to: CGPoint(x: centerX - hipX, y: hipTop))
        path.addLine(to: CGPoint(x: centerX - hipX, y: bottom))

        // Right waist to hip
        path.move(to: CGPoint(x: centerX + waistX, y: waistTop))
        path.addLine(to: CGPoint(x: centerX + hipX, y: hipTop))
        path.addLine(to: CGPoint(x: centerX + hipX, y: bottom))

        // Arms (simplified straight lines from shoulders)
        let armWidth = width * 0.08
        let armEndY = waistTop

        // Left arm
        path.move(to: CGPoint(x: centerX - shoulderX, y: shoulderTop))
        path.addLine(to: CGPoint(x: centerX - shoulderX - armWidth * 2, y: armEndY))

        // Right arm
        path.move(to: CGPoint(x: centerX + shoulderX, y: shoulderTop))
        path.addLine(to: CGPoint(x: centerX + shoulderX + armWidth * 2, y: armEndY))

        return path
    }

    /// Classify body type based on body fat percentage
    private func classifyBodyType(bodyFat: Double, isMale: Bool) -> BodyType {
        if isMale {
            switch bodyFat {
            case ..<10:
                return .veryLeanMale
            case 10..<15:
                return .leanMale
            case 15..<20:
                return .averageMale
            case 20..<25:
                return .moderateMale
            default:
                return .higherMale
            }
        } else {
            switch bodyFat {
            case ..<15:
                return .veryLeanFemale
            case 15..<20:
                return .leanFemale
            case 20..<25:
                return .averageFemale
            case 25..<30:
                return .moderateFemale
            default:
                return .higherFemale
            }
        }
    }
}

/// Body type classifications with dimension ratios
enum BodyType {
    // Male body types
    case veryLeanMale
    case leanMale
    case averageMale
    case moderateMale
    case higherMale

    // Female body types
    case veryLeanFemale
    case leanFemale
    case averageFemale
    case moderateFemale
    case higherFemale

    /// Returns (shoulderWidth, waistWidth, hipWidth, neckWidth) as ratios
    var dimensions: (Double, Double, Double, Double) {
        switch self {
        // Male body types (wider shoulders, narrower hips)
        case .veryLeanMale:
            return (0.95, 0.60, 0.65, 0.20) // Very lean: wide shoulders, very narrow waist
        case .leanMale:
            return (0.90, 0.65, 0.68, 0.22) // Lean: wide shoulders, narrow waist
        case .averageMale:
            return (0.85, 0.72, 0.72, 0.24) // Average: moderate taper
        case .moderateMale:
            return (0.82, 0.78, 0.75, 0.26) // Moderate: less taper
        case .higherMale:
            return (0.80, 0.85, 0.80, 0.28) // Higher BF: minimal taper

        // Female body types (narrower shoulders, wider hips)
        case .veryLeanFemale:
            return (0.75, 0.58, 0.75, 0.18) // Very lean: narrow waist, defined
        case .leanFemale:
            return (0.72, 0.62, 0.78, 0.19) // Lean: feminine taper
        case .averageFemale:
            return (0.70, 0.68, 0.80, 0.20) // Average: balanced proportions
        case .moderateFemale:
            return (0.68, 0.74, 0.82, 0.21) // Moderate: softer curves
        case .higherFemale:
            return (0.66, 0.80, 0.85, 0.22) // Higher BF: fuller figure
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        AvatarBodyRenderer(bodyFatPercentage: 12, gender: "male", height: 200)
        AvatarBodyRenderer(bodyFatPercentage: 22, gender: "female", height: 200)
        AvatarBodyRenderer(bodyFatPercentage: nil, gender: "male", height: 200)
    }
    .padding()
    .background(Color.gray)
}
