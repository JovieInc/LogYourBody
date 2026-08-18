import SwiftUI
import UIKit

struct BugReportPromptSheet: View {
    @EnvironmentObject var bugReportManager: BugReportManager
    @State private var sheetDetent = NativeSheetPresentationPolicy.initialDetent(for: .bugReportPrompt)

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Tell us what happened. A screenshot is optional and may include whatever is visible on screen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }

                Section {
                    Toggle(isOn: $bugReportManager.isShakeToReportEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Shake iPhone to report a bug")
                            Text("Toggle off to disable")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.appPrimary)
                }
            }
            .navigationTitle("Report a problem")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button("Report a problem") {
                    HapticManager.shared.buttonTap()
                    bugReportManager.presentFormFromPrompt()
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
            }
        }
        .nativeSheetChrome(for: .bugReportPrompt, detent: $sheetDetent)
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
        NavigationStack {
            Form {
                Section {
                    messageField
                } header: {
                    Text("Tell us what happened")
                } footer: {
                    Text(characterCountText)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                Section {
                    infoText
                }

                screenshotSection
            }
            .navigationTitle("Report a problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .cancellationAction) {
                    Button("Cancel") {
                        HapticManager.shared.selection()
                        bugReportManager.cancel()
                        dismiss()
                    }
                }

                ToolbarItemGroup(placement: .confirmationAction) {
                    Button("Send") {
                        HapticManager.shared.buttonTap()
                        bugReportManager.submit()
                        dismiss()
                    }
                    .disabled(!bugReportManager.canSubmit)
                }
            }
        }
        .onAppear {
            AppServicePorts.analyticsTracker.track(
                event: "bug_report_form_opened",
                properties: [
                    "has_screenshot": bugReportManager.screenshotData != nil ? "true" : "false"
                ]
            )
        }
        .worldClassScreen(.bugReport)
    }

    private var messageField: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $bugReportManager.message)
                .focused($isTextEditorFocused)
                .frame(minHeight: 160)
                .onChange(of: bugReportManager.message) { _, newValue in
                    if newValue.count > BugReportManager.maxMessageLength {
                        bugReportManager.message = String(newValue.prefix(BugReportManager.maxMessageLength))
                    }
                }

            if bugReportManager.message.isEmpty {
                Text("What did you expect, and what happened instead?")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .padding(.leading, 4)
                    .allowsHitTesting(false)
            }
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
    }

    private var infoText: some View {
        let supportLink = Text("contact support.")
            .foregroundStyle(Color.appPrimary)
        let combined = Text(
            "Reports include your description and basic app and device details. Screenshots are optional. " +
                "If you have additional questions, \(supportLink)"
        )

        return combined
            .font(.footnote)
            .foregroundStyle(.secondary)
            .onTapGesture {
                openSupport()
            }
    }

    @ViewBuilder
    private var screenshotSection: some View {
        Section {
            Toggle("Include screenshot in report", isOn: $bugReportManager.includeScreenshot)
                .tint(.appPrimary)

            if let data = bugReportManager.screenshotData,
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityLabel("Screenshot included in report")
            }
        }
    }

    private func openSupport() {
        guard let url = URL(string: "mailto:\(ProductRegistry.supportEmail)") else {
            return
        }

        UIApplication.shared.open(url)
    }
}
