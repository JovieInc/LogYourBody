//
//  AvatarBodyRenderer.swift
//  LogYourBody
//
//  Renders static body-fat bucket avatars.
//

import SwiftUI

struct AvatarBodyRenderer: View {
    let bodyFatPercentage: Double?
    let gender: String?
    let height: CGFloat
    var padding: CGFloat = 12
    var verticalPadding: CGFloat = 0
    var horizontalFillScale: CGFloat = 1
    var alignment: Alignment = .center

    private var avatar: AvatarBodyFatCatalog.Match {
        AvatarBodyFatCatalog.match(bodyFatPercentage: bodyFatPercentage, gender: gender)
    }

    private var clampedHorizontalFillScale: CGFloat {
        max(horizontalFillScale, 1)
    }

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = max(0, geometry.size.width - padding * 2)
            let contentHeight = max(0, geometry.size.height - verticalPadding * 2)

            Image(avatar.assetName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(
                    width: contentWidth * clampedHorizontalFillScale,
                    height: contentHeight,
                    alignment: alignment
                )
                .frame(width: contentWidth, height: contentHeight, alignment: alignment)
                .clipped()
                .padding(.horizontal, padding)
                .padding(.vertical, verticalPadding)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: alignment)
                .clipped()
                .accessibilityHidden(true)
        }
        .frame(height: height)
        .accessibilityLabel(avatar.accessibilityLabel)
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
