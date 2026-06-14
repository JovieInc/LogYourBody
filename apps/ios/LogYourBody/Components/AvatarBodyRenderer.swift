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
        ZStack {
            Color.black

            Image(avatar.assetName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .padding(.horizontal, 10)
                .padding(.vertical, 14)
                .shadow(color: Color.metricAccent.opacity(0.36), radius: 16)
                .accessibilityHidden(true)
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
