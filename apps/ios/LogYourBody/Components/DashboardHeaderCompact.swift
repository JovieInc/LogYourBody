import SwiftUI

struct DashboardHeaderCompact: View {
    let avatarURL: URL?
    let userFirstName: String
    let hasAge: Bool
    let hasHeight: Bool
    let syncStatusTitle: String
    let syncStatusDetail: String?
    let syncStatusColor: Color
    let isSyncError: Bool
    let onShowSyncDetails: () -> Void

    @State private var isSyncIndicatorExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                NavigationLink(destination: PreferencesView()) {
                    avatarView
                }
                .buttonStyle(PlainButtonStyle())

                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome back")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(Color.liquidTextPrimary.opacity(0.7))
                        .lineLimit(1)

                    Text(userFirstName)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color.liquidTextPrimary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                syncIndicator
            }

            if !hasAge || !hasHeight {
                HStack(spacing: 8) {
                    if !hasAge {
                        NavigationLink(destination: PreferencesView()) {
                            Text("Add age")
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

                    if !hasHeight {
                        NavigationLink(destination: PreferencesView()) {
                            Text("Add height")
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
            }
        }
    }

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(Color.white.opacity(0.1))
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1.5)
                )
                .frame(width: 36, height: 36)

            if let url = avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure, .empty:
                        Image(systemName: "person.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color.liquidTextPrimary.opacity(0.7))
                    @unknown default:
                        Image(systemName: "person.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color.liquidTextPrimary.opacity(0.7))
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color.liquidTextPrimary.opacity(0.7))
            }
        }
    }

    private var syncIndicator: some View {
        Button {
            onShowSyncDetails()
        } label: {
            HStack(spacing: 8) {
                if isSyncIndicatorExpanded, isSyncError {
                    Text(syncIndicatorLabelText)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.liquidTextPrimary.opacity(0.7))
                        .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 999)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .clipShape(Capsule())
                    .transition(
                        .move(edge: .trailing)
                            .combined(with: .opacity)
                    )
                }

                Circle()
                    .fill(syncStatusColor)
                    .frame(width: 6, height: 6)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            handleSyncIndicatorStatusChange()
        }
        .onChange(of: isSyncError) { _, _ in
            handleSyncIndicatorStatusChange()
        }
    }

    private var syncIndicatorLabelText: String {
        guard isSyncError else {
            return syncStatusTitle
        }

        return "Sync paused (tap for details)"
    }

    private func handleSyncIndicatorStatusChange() {
        guard isSyncError else {
            withAnimation(.easeOut(duration: 0.25)) {
                isSyncIndicatorExpanded = false
            }
            return
        }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isSyncIndicatorExpanded = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            withAnimation(.easeOut(duration: 0.25)) {
                isSyncIndicatorExpanded = false
            }
        }
    }
}
