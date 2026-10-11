import SwiftUI

/// The first screen asks where the person's numbers already live. A DEXA or
/// InBody report is the primary path for existing body-composition data;
/// Apple Health and typing the numbers are the alternatives.
struct BodyScoreHookView: View {
    @ObservedObject var viewModel: OnboardingFlowViewModel
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isSelectingScan = false
    @State private var selectedScan: DexaPDFFileSelection?
    @State private var scanPickerError: String?

    static let scanImportFixtureArgument = "-lybUITestOnboardingScanImportFixture"

    private var offersScanImport: Bool {
        viewModel.entryContext == .authenticated
    }

    var body: some View {
        OnboardingPageTemplate(
            title: "Are you losing fat or lean mass?",
            subtitle: "Start with the numbers you already have.",
            showsBackButton: false,
            progress: viewModel.progress(for: .hook),
            screen: .bodyScoreIntro
        ) {
            VStack(spacing: 16) {
                if !dynamicTypeSize.isAccessibilitySize {
                    BodyScoreContourField()
                        .frame(height: 170)
                }

                if let scanPickerError {
                    Text(scanPickerError)
                        .font(OnboardingTypography.caption)
                        .foregroundStyle(Color.appError)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("body_score_onboarding_scan_error")
                }

                if dynamicTypeSize.isAccessibilitySize {
                    alternativeActions
                }
            }
        } footer: {
            VStack(spacing: 12) {
                primaryAction

                if !dynamicTypeSize.isAccessibilitySize {
                    alternativeActions
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("body_score_onboarding_hook_footer")
        }
        .fileImporter(
            isPresented: $isSelectingScan,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    selectedScan = DexaPDFFileSelection(url: url)
                }
            case .failure:
                scanPickerError = "Choose a readable DEXA or InBody PDF and try again."
            }
        }
        .sheet(item: $selectedScan) { selection in
            DexaPDFImportSheet(fileURL: selection.url) { scans in
                viewModel.applyImportedScans(scans)
            }
            .environmentObject(authManager)
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if offersScanImport {
            Button(action: startScanImport) {
                Label("Import a DEXA or InBody scan", systemImage: "doc.text.viewfinder")
            }
            .accessibilityIdentifier("body_score_onboarding_import_scan_button")
            .buttonStyle(OnboardingPrimaryButtonStyle())
        } else {
            Button {
                viewModel.chooseHealthPath()
            } label: {
                Label("Use Apple Health", systemImage: "heart.fill")
            }
            .accessibilityIdentifier("body_score_onboarding_use_health_button")
            .buttonStyle(OnboardingPrimaryButtonStyle())
        }
    }

    private var alternativeActions: some View {
        VStack(spacing: 12) {
            if offersScanImport {
                Button {
                    viewModel.chooseHealthPath()
                } label: {
                    Label("Use Apple Health", systemImage: "heart.fill")
                }
                .accessibilityIdentifier("body_score_onboarding_use_health_button")
                .buttonStyle(OnboardingSecondaryButtonStyle())
            }

            OnboardingTextButton(title: "Enter my numbers") {
                viewModel.chooseManualPath()
            }
            .accessibilityIdentifier("body_score_onboarding_start_button")

            if viewModel.entryContext == .preAuth {
                OnboardingTextButton(title: "I already have an account") {
                    dismiss()
                }
            }
        }
    }

    private func startScanImport() {
        scanPickerError = nil
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(Self.scanImportFixtureArgument) {
            viewModel.applyImportedScans(Self.fixtureScans)
            return
        }
        #endif
        isSelectingScan = true
    }

    #if DEBUG
    /// Two BodySpec-style scans, so UI tests can cover the "what changed" reveal
    /// without the Files picker or the parser endpoint.
    static let fixtureScans: [DexaPDFScan] = [
        DexaPDFScan(
            date: "2026-06-02", weight: 186, weightUnit: "lbs", bodyFatPercentage: 22,
            muscleMass: nil, boneMass: nil, source: "BodySpec"
        ),
        DexaPDFScan(
            date: "2026-09-01", weight: 180, weightUnit: "lbs", bodyFatPercentage: 19,
            muscleMass: nil, boneMass: nil, source: "BodySpec"
        )
    ]
    #endif
}

private struct BodyScoreContourField: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width * 0.5, y: size.height * 0.52)
            let maximum = min(size.width, size.height) * 0.82

            for ring in 0..<9 {
                let progress = CGFloat(ring) / 8
                let width = maximum * (0.2 + progress * 0.8)
                let height = width * (0.58 + progress * 0.18)
                let rect = CGRect(
                    x: center.x - width / 2,
                    y: center.y - height / 2,
                    width: width,
                    height: height
                )
                let color = ring.isMultiple(of: 2) ? theme.colors.info : theme.colors.accentPink
                context.stroke(
                    Path(ellipseIn: rect),
                    with: .color(color.opacity(0.14 + Double(8 - ring) * 0.016)),
                    lineWidth: ring == 0 ? 1.5 : 1
                )
            }
        }
        .background {
            RadialGradient(
                colors: [theme.colors.info.opacity(JovieTokens.ambientAccentOpacity), .clear],
                center: .center,
                startRadius: 4,
                endRadius: 150
            )
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    BodyScoreHookView(viewModel: OnboardingFlowViewModel())
        .environmentObject(AuthManager.shared)
        .preferredColorScheme(.dark)
}
