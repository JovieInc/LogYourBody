import SwiftUI
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
}
