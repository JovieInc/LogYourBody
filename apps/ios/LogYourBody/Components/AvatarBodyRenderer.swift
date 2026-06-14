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

    private var avatar: AvatarBodyFatCatalog.Match {
        AvatarBodyFatCatalog.match(bodyFatPercentage: bodyFatPercentage, gender: gender)
    }

    var body: some View {
        GeometryReader { geometry in
            Image(avatar.assetName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .shadow(color: Color.metricAccent.opacity(0.36), radius: 16)
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
