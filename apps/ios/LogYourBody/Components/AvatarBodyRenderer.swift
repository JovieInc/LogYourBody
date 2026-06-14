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
    var alignment: Alignment = .center

    private var avatar: AvatarBodyFatCatalog.Match {
        AvatarBodyFatCatalog.match(bodyFatPercentage: bodyFatPercentage, gender: gender)
    }

    var body: some View {
        GeometryReader { geometry in
            Image(avatar.assetName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(
                    width: max(0, geometry.size.width - padding * 2)
                )
                .padding(padding)
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
