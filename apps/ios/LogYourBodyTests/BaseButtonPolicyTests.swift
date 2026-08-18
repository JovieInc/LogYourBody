import XCTest
@testable import LogYourBody

final class BaseButtonPolicyTests: XCTestCase {
    func testDefaultPrimaryButtonUsesCapsuleAndMeetsHitTarget() {
        let configuration = ButtonConfiguration()

        XCTAssertNil(configuration.cornerRadius)
        XCTAssertEqual(configuration.size.height, JovieTokens.controlHeight)
        XCTAssertGreaterThanOrEqual(configuration.size.height, JovieTokens.minimumHitTarget)
        XCTAssertGreaterThanOrEqual(
            max(configuration.size.height, JovieTokens.minimumHitTarget),
            44
        )
    }

    func testAllStandardButtonSizesMeetFortyFourPointHitTarget() {
        XCTAssertGreaterThanOrEqual(
            ButtonConfiguration.ButtonSizeVariant.small.height,
            JovieTokens.minimumHitTarget
        )
        XCTAssertGreaterThanOrEqual(
            ButtonConfiguration.ButtonSizeVariant.medium.height,
            JovieTokens.minimumHitTarget
        )
        XCTAssertGreaterThanOrEqual(
            ButtonConfiguration.ButtonSizeVariant.large.height,
            JovieTokens.minimumHitTarget
        )
    }

    func testLiquidGlassCTAUsesCanonicalPillHeight() {
        XCTAssertEqual(JovieTokens.controlHeight, 52)
        XCTAssertGreaterThanOrEqual(JovieTokens.controlHeight, JovieTokens.minimumHitTarget)
        XCTAssertEqual(
            ButtonConfiguration(size: .medium).size.height,
            JovieTokens.controlHeight
        )
    }
}
