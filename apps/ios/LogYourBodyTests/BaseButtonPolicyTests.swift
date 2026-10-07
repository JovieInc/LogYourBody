import SwiftUI
import UIKit
import XCTest
@testable import LogYourBody

final class BaseButtonPolicyTests: XCTestCase {
    func testDefaultPrimaryButtonUsesCapsuleAtLockedActionHeight() {
        let configuration = ButtonConfiguration()

        // r999: no explicit radius means Capsule.
        XCTAssertNil(configuration.cornerRadius)
        // 32 visible / >= 44 tap (ActionButton 32/510/r999, cta-32-44).
        XCTAssertEqual(BaseButtonGeometry.visibleHeight(for: configuration.size), JovieTokens.actionControlHeight)
        XCTAssertEqual(BaseButtonGeometry.visibleHeight(for: configuration.size), 32)
        XCTAssertGreaterThanOrEqual(
            BaseButtonGeometry.tapTargetHeight(for: configuration.size),
            JovieTokens.minimumHitTarget
        )
    }

    func testAllStandardButtonSizesShareTheLockedVisibleHeightAndMeetTapTarget() {
        let sizes: [ButtonConfiguration.ButtonSizeVariant] = [.small, .medium, .large]
        for size in sizes {
            XCTAssertEqual(BaseButtonGeometry.visibleHeight(for: size), JovieTokens.actionControlHeight)
            XCTAssertGreaterThanOrEqual(BaseButtonGeometry.tapTargetHeight(for: size), 44)
            XCTAssertEqual(size.padding.top, 0)
            XCTAssertEqual(size.padding.bottom, 0)
            XCTAssertEqual(size.padding.leading.truncatingRemainder(dividingBy: 4), 0)
        }
    }

    func testCustomSizeKeepsCallerHeightButStillMeetsTapTarget() {
        let custom = ButtonConfiguration.ButtonSizeVariant.custom(
            height: 24,
            padding: EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8),
            fontSize: 12
        )
        XCTAssertEqual(BaseButtonGeometry.visibleHeight(for: custom), 24)
        XCTAssertEqual(BaseButtonGeometry.tapTargetHeight(for: custom), JovieTokens.minimumHitTarget)
    }

    func testActionLabelWeightIsFiveTenNotSemibold() {
        XCTAssertEqual(JovieTokens.actionLabelWeight, .medium)
    }

    func testInputControlHeightStaysSeparateFromTheActionAtom() {
        // Inputs and the chat composer keep the 52pt control; only the CTA family is 32.
        XCTAssertEqual(JovieTokens.controlHeight, 52)
        XCTAssertEqual(JovieTokens.actionControlHeight, 32)
        XCTAssertEqual(ButtonSize.medium.height, JovieTokens.actionControlHeight)
    }

    @MainActor
    func testLoadingParityOnlyUsesItsOwnGate() {
        var requestedKeys: [String] = []
        XCTAssertFalse(BaseButtonLoadingPolicy.isEnabled { key in
            requestedKeys.append(key)
            return false
        })
        XCTAssertTrue(BaseButtonLoadingPolicy.isEnabled { key in
            requestedKeys.append(key)
            return key == BaseButtonLoadingPolicy.gateKey
        })
        XCTAssertEqual(requestedKeys, Array(repeating: "native_button_loading_parity_v1", count: 2))
    }

    @MainActor
    func testLoadingRetainsIntrinsicWidthAndHeightAcrossDynamicType() {
        let sizes: [DynamicTypeSize] = [.large, .xxxLarge, .accessibility1, .accessibility3, .accessibility5]
        for size in sizes {
            let idle = fittingSize(isLoading: false, typeSize: size)
            let loading = fittingSize(isLoading: true, typeSize: size)
            XCTAssertEqual(loading.width, idle.width, accuracy: 0.5, "Loading changed the width at \(size)")
            XCTAssertEqual(loading.height, idle.height, accuracy: 0.5, "Loading changed the height at \(size)")
            XCTAssertGreaterThanOrEqual(loading.height, JovieTokens.minimumHitTarget)
        }
    }

    @MainActor
    func testLoadingKeepsWrappedLabelHeightAtNarrowWidths() {
        for width: CGFloat in [160, 240, 320] {
            let idle = fittingSize(isLoading: false, typeSize: .accessibility3, width: width)
            let loading = fittingSize(isLoading: true, typeSize: .accessibility3, width: width)
            XCTAssertGreaterThan(idle.height, JovieTokens.minimumHitTarget)
            XCTAssertEqual(loading.width, idle.width, accuracy: 0.5)
            XCTAssertEqual(loading.height, idle.height, accuracy: 0.5)
        }
    }

    @MainActor
    func testLoadingRetainsFullWidthAndCustomControlGeometry() {
        for fullWidth in [false, true] {
            let configuration = ButtonConfiguration(
                size: .custom(height: 60, padding: EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16), fontSize: 16),
                fullWidth: fullWidth,
                icon: "arrow.up",
                iconPosition: .trailing
            )
            let idle = fittingSize(isLoading: false, typeSize: .large, configuration: configuration)
            let loading = fittingSize(isLoading: true, typeSize: .large, configuration: configuration)
            XCTAssertEqual(loading.width, idle.width, accuracy: 0.5)
            XCTAssertEqual(loading.height, idle.height, accuracy: 0.5)
            XCTAssertGreaterThanOrEqual(loading.height, 60)
        }
    }

    @MainActor
    func testGateOffPreservesTheExistingLoadingPresentation() {
        let idle = fittingSize(isLoading: false, typeSize: .large, parityEnabled: false)
        let loading = fittingSize(isLoading: true, typeSize: .large, parityEnabled: false)
        XCTAssertLessThan(loading.width, idle.width, "The rollout must preserve the gate-off path")
        XCTAssertEqual(loading.height, JovieTokens.minimumHitTarget, accuracy: 0.5)
    }

    @MainActor
    func testLoadingButtonGrowsWithDynamicTypeInsteadOfClippingToTheAtomHeight() {
        let normal = fittingSize(isLoading: true, typeSize: .large)
        let accessible = fittingSize(isLoading: true, typeSize: .accessibility5)
        XCTAssertGreaterThan(accessible.height, normal.height)
    }

    @MainActor
    func testCaptureIdleAndLoadingComponentEvidence() throws {
        for parityEnabled in [false, true] {
            for typeSize: DynamicTypeSize in [.large, .accessibility3] {
                for isLoading in [false, true] {
                    let component = BaseButton(
                        "Add to timeline",
                        configuration: ButtonConfiguration(isLoading: isLoading, icon: "arrow.up"),
                        action: {}
                    )
                    .environment(\.baseButtonLoadingParity, parityEnabled)
                    .environment(\.dynamicTypeSize, typeSize)
                    .transaction {
                        $0.animation = nil
                        $0.disablesAnimations = true
                    }
                    .padding(JovieTokens.screenInset)
                    .background(Color.appBackground)
                    .preferredColorScheme(.dark)
                    let renderer = ImageRenderer(content: component)
                    renderer.proposedSize = ProposedViewSize(width: 320, height: nil)
                    renderer.scale = 2
                    let rendered = try XCTUnwrap(renderer.uiImage)
                    let attachment = XCTAttachment(image: rendered)
                    attachment.name = "button-\(parityEnabled ? "after" : "before")-\(isLoading ? "loading" : "idle")-\(typeSize)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                }
            }
        }
    }

    @MainActor
    private func fittingSize(
        isLoading: Bool,
        typeSize: DynamicTypeSize,
        width: CGFloat = 320,
        configuration: ButtonConfiguration = ButtonConfiguration(icon: "arrow.up"),
        parityEnabled: Bool = true
    ) -> CGSize {
        var configuration = configuration
        configuration.isLoading = isLoading
        let host = UIHostingController(rootView: BaseButton("Add to timeline", configuration: configuration, action: {})
            .environment(\.baseButtonLoadingParity, parityEnabled)
            .environment(\.dynamicTypeSize, typeSize))
        return host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }
}
