import SwiftUI

struct DashboardHeaderCompact: View {
    let avatarURL: URL?
    let userFirstName: String
    let userAgeDisplay: String
    let userHeightDisplay: String
    let syncStatusTitle: String
    let syncStatusDetail: String?
    let syncStatusColor: Color
    let onShowSyncDetails: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            NavigationLink(destination: PreferencesView()) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.1))
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1.5)
                        )
                        .frame(width: 44, height: 44)

                    if let url = avatarURL {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            case .failure, .empty:
                                Image(systemName: "person.fill")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(Color.liquidTextPrimary.opacity(0.7))
                            @unknown default:
                                Image(systemName: "person.fill")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(Color.liquidTextPrimary.opacity(0.7))
                            }
                        }
                        .frame(width: 44, height: 44)
                        .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(Color.liquidTextPrimary.opacity(0.7))
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome back, \(userFirstName)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color.liquidTextPrimary)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    NavigationLink(destination: PreferencesView()) {
                        Text("Age: \(userAgeDisplay)")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 999)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                            .foregroundColor(Color.liquidTextPrimary.opacity(0.8))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())

                    NavigationLink(destination: PreferencesView()) {
                        Text("Height: \(userHeightDisplay)")
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 999)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                            .foregroundColor(Color.liquidTextPrimary.opacity(0.8))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }

            Spacer(minLength: 8)

            Button {
                onShowSyncDetails()
            } label: {
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(syncStatusColor)
                            .frame(width: 6, height: 6)
                        Text(syncStatusTitle)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(Color.liquidTextPrimary.opacity(0.6))
                            .lineLimit(1)
                    }

                    if let detail = syncStatusDetail {
                        Text(detail)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(Color.liquidTextPrimary.opacity(0.5))
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(PlainButtonStyle())
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
