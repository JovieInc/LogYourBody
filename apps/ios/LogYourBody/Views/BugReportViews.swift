import SwiftUI
import UIKit

struct BugReportPromptSheet: View {
    @EnvironmentObject var bugReportManager: BugReportManager

    var body: some View {
        VStack(spacing: 24) {
            Capsule()
                .fill(Color.white.opacity(0.4))
                .frame(width: 40, height: 4)
                .padding(.top, 8)

            Text("Report a bug?")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.appText)

            Text("If something isn't working correctly, you can report it to help improve LogYourBody for everyone.")
                .font(.subheadline)
                .foregroundColor(.appTextSecondary)
                .multilineTextAlignment(.center)

            Button(action: {
                HapticManager.shared.buttonTap()
                bugReportManager.presentFormFromPrompt()
            }) {
                Text("Report bug")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.white)
                    .foregroundColor(.black)
                    .clipShape(Capsule())
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Shake iPhone to report a bug")
                        .font(.subheadline)
                        .foregroundColor(.appText)

                    Text("Toggle off to disable")
                        .font(.caption)
                        .foregroundColor(.appTextSecondary)
                }

                Spacer()

                Toggle("", isOn: $bugReportManager.isShakeToReportEnabled)
                    .labelsHidden()
                    .tint(.appPrimary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .background(
            Color.appBackground
                .ignoresSafeArea()
        )
    }
}

struct BugReportFormView: View {
    @EnvironmentObject var bugReportManager: BugReportManager
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isTextEditorFocused: Bool

    private var characterCountText: String {
        let count = bugReportManager.message.count
        return "\(count)/\(BugReportManager.maxMessageLength)"
    }

    var body: some View {
        ZStack {
            Color.appBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("What happened?")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.appText)

                        messageField

                        infoText

                        screenshotSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            bottomBar
        }
        .onAppear {
            AnalyticsService.shared.track(
                event: "bug_report_form_opened",
                properties: [
                    "has_screenshot": bugReportManager.screenshotData != nil ? "true" : "false"
                ]
            )
        }
    }

    private var header: some View {
        HStack {
            Spacer()

            Text("Report bug")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.appText)

            Spacer()

            Button(action: {
                HapticManager.shared.selection()
                bugReportManager.cancel()
                dismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .padding(8)
                    .background(Color.white.opacity(0.15))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    private var messageField: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.appCard)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.appBorder, lineWidth: 1)
                )

            TextEditor(text: $bugReportManager.message)
                .focused($isTextEditorFocused)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 180, maxHeight: 200)
                .onChange(of: bugReportManager.message) { _, newValue in
                    if newValue.count > BugReportManager.maxMessageLength {
                        bugReportManager.message = String(newValue.prefix(BugReportManager.maxMessageLength))
                    }
                }

            if bugReportManager.message.isEmpty {
                Text("Tell us about the issue you encountered")
                    .font(.body)
                    .foregroundColor(.appTextSecondary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 18)
            }

            VStack {
                Spacer()

                HStack {
                    Spacer()

                    Text(characterCountText)
                        .font(.caption2)
                        .foregroundColor(.appTextSecondary)
                        .padding(.trailing, 14)
                        .padding(.bottom, 8)
                }
            }
        }
    }

    private var infoText: some View {
        let combined = Text("Any information you share may be reviewed to help improve LogYourBody. If you have additional questions, ") +
            Text("contact support.")
            .foregroundColor(.appPrimary)

        return combined
            .font(.footnote)
            .foregroundColor(.appTextSecondary)
            .multilineTextAlignment(.leading)
            .onTapGesture {
                openSupport()
            }
    }

    private var screenshotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Include screenshot in report")
                    .font(.subheadline)
                    .foregroundColor(.appText)

                Spacer()

                Toggle("", isOn: $bugReportManager.includeScreenshot)
                    .labelsHidden()
                    .tint(.appPrimary)
            }

            if let data = bugReportManager.screenshotData,
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 200)
                    .clipped()
                    .cornerRadius(16)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.appBorder, lineWidth: 1)
                    )
            }
        }
    }

    private var bottomBar: some View {
        VStack(spacing: 12) {
            Button(action: {
                HapticManager.shared.buttonTap()
                bugReportManager.submit()
                dismiss()
            }) {
                Text("Send")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(bugReportManager.canSubmit ? Color.white : Color.white.opacity(0.3))
                    .foregroundColor(.black)
                    .clipShape(Capsule())
            }
            .disabled(!bugReportManager.canSubmit)
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 8)
        }
        .background(
            Color.appBackground
                .opacity(0.95)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func openSupport() {
        guard let url = URL(string: "mailto:support@logyourbody.com") else {
            return
        }

        UIApplication.shared.open(url)
    }
}
