//
// PreferencesView+Header.swift
// LogYourBody
//
import SwiftUI

extension PreferencesView {
    var heroHeader: some View {
        VStack(spacing: 16) {
            HStack(alignment: .center, spacing: 16) {
                heroAvatar

                VStack(alignment: .leading, spacing: 4) {
                    Text(userDisplayName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.appText)

                    Text(userEmail)
                        .font(.subheadline)
                        .foregroundColor(.appTextSecondary)

                    if let memberSinceText {
                        Text(memberSinceText)
                            .font(.caption)
                            .foregroundColor(.appTextSecondary)
                    }
                }

                Spacer()
            }

            statusBadge
        }
        .padding(20)
        .background(Color.appCard)
        .cornerRadius(16)
    }

    var compactHeader: some View {
        VStack(spacing: 0) {
            HStack {
                heroAvatarSmall
                Text(userDisplayName)
                    .font(.headline)
                    .foregroundColor(.appText)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, topSafeArea + 8)
            .padding(.bottom, 12)
            .background(Color.appBackground.opacity(0.95))
            .opacity(scrollOffset < -60 ? 1 : 0)
        }
        .ignoresSafeArea(edges: .top)
        .animation(.easeInOut(duration: 0.2), value: scrollOffset)
    }

    var heroAvatar: some View {
        ZStack {
            if let profileAvatarURLString,
               let url = URL(string: profileAvatarURLString) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    avatarPlaceholder
                }
                .frame(width: 72, height: 72)
                .clipShape(Circle())
            } else {
                avatarPlaceholder
                    .frame(width: 72, height: 72)
            }

            if isUploadingPhoto {
                Circle()
                    .fill(Color.black.opacity(0.45))
                    .frame(width: 72, height: 72)

                ProgressView(value: avatarUploadProgress)
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.8)
            }
        }
    }

    var heroAvatarSmall: some View {
        ZStack {
            if let profileAvatarURLString,
               let url = URL(string: profileAvatarURLString) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    avatarPlaceholder
                }
                .frame(width: 32, height: 32)
                .clipShape(Circle())
            } else {
                avatarPlaceholder
                    .frame(width: 32, height: 32)
            }
        }
    }

    var statusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(revenueCatManager.isSubscribed ? Color.green : Color.orange)
                .frame(width: 8, height: 8)

            Text(subscriptionStatusText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.appTextSecondary)

            if let planDisplay = subscriptionPlanDisplay {
                Text("•")
                    .foregroundColor(.appTextTertiary)
                Text(planDisplay)
                    .font(.caption)
                    .foregroundColor(.appTextSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var avatarPlaceholder: some View {
        Circle()
            .fill(Color.white.opacity(0.1))
            .overlay(
                Text(userInitials)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
            )
    }
}
