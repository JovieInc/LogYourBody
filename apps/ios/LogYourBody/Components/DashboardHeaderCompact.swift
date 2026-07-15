import SwiftUI

struct DashboardHeaderCompact: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let scrollProgress: CGFloat
    let avatarURL: URL?
    let userFirstName: String
    let hasAge: Bool
    let hasHeight: Bool
    let syncStatusTitle: String
    let syncStatusDetail: String?
    let syncStatusColor: Color
    let isSyncError: Bool
    let onShowSyncDetails: () -> Void
    let onAddEntry: () -> Void

    private var clampedScrollProgress: CGFloat {
        min(max(scrollProgress, 0), 1)
    }

    private var shouldShowPersistentSyncStatus: Bool {
        isSyncError || syncStatusTitle == "Offline"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                NavigationLink(destination: PreferencesView()) {
                    avatarView
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .accessibilityLabel("Open profile and settings")

                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome back")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(
                            Color.liquidTextPrimary.opacity(0.7 - 0.2 * clampedScrollProgress)
                        )
                        .lineLimit(1)

                    Text(userFirstName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.liquidTextPrimary)
                        .lineLimit(1)
                        .offset(y: -3 * clampedScrollProgress)
                }
                .animation(
                    reduceMotion ? nil : .easeOut(duration: 0.2),
                    value: clampedScrollProgress
                )

                Spacer(minLength: 8)

                Button {
                    onAddEntry()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.white)
                        .frame(width: 28, height: 28)
                        .background(
                            Circle()
                                .fill(Color.appPrimary)
                        )
                }
                .frame(width: 44, height: 44)
                .contentShape(Circle())
                .buttonStyle(.plain)
                .accessibilityLabel("New Entry")
                .accessibilityHint("Opens a new body metric entry")
            }

            if shouldShowPersistentSyncStatus {
                syncStatusNotice
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
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                        .contentShape(Capsule())
                        .accessibilityLabel("Add your age")
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
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                        .contentShape(Capsule())
                        .accessibilityLabel("Add your height")
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

    private var syncStatusNotice: some View {
        Button {
            onShowSyncDetails()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: syncStatusSymbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(syncStatusColor)
                    .frame(width: 20, height: 20)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(syncStatusTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Color.liquidTextPrimary)

                    Text(syncStatusDetailText)
                        .font(.footnote)
                        .foregroundColor(Color.liquidTextPrimary.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color.liquidTextPrimary.opacity(0.55))
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(syncStatusColor.opacity(0.42), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(syncStatusTitle). \(syncStatusDetailText)")
        .accessibilityHint("Opens sync details and recovery options")
        .accessibilityIdentifier("dashboard_sync_status")
    }

    private var syncStatusSymbolName: String {
        if isSyncError {
            return "exclamationmark.triangle.fill"
        }

        return "icloud.slash.fill"
    }

    private var syncStatusDetailText: String {
        if let syncStatusDetail, !syncStatusDetail.isEmpty {
            return syncStatusDetail
        }

        return isSyncError
            ? "Tap for sync details and retry options."
            : "Changes are queued until you are back online."
    }
}
