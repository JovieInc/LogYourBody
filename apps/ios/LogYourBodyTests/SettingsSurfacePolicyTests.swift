import XCTest
@testable import LogYourBody

final class SettingsSurfacePolicyTests: XCTestCase {
    func testSettingsRootUsesTheAccountWorldClassScreen() {
        XCTAssertEqual(SettingsSurfacePolicy.settingsScreen, .settings)
        XCTAssertEqual(WorldClassScreen.settings.flow, .account)
        XCTAssertEqual(
            SettingsSurfacePolicy.settingsScreen.accessibilityIdentifier,
            "world_class_screen_settings"
        )
    }

    func testSettingsRootExposesStableAccessibilityIdentifiers() {
        let identifiers = SettingsSurfacePolicy.rootAccessibilityIdentifiers

        XCTAssertEqual(
            identifiers,
            [
                "settings_profile_link",
                "settings_tracking_link",
                "settings_integrations_link",
                "settings_account_subscription_link",
                "settings_privacy_data_link",
                "world_class_screen_settings"
            ]
        )
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        XCTAssertTrue(identifiers.contains(WorldClassScreen.settings.accessibilityIdentifier))
    }

    func testNestedSettingsSurfacesKeepKnownIdentifiers() {
        let identifiers = SettingsSurfacePolicy.nestedAccessibilityIdentifiers

        XCTAssertTrue(identifiers.contains("settings_logout_button"))
        XCTAssertTrue(identifiers.contains("settings_profile_height_row"))
        XCTAssertTrue(identifiers.contains("settings_units_row"))
        XCTAssertTrue(identifiers.contains("settings_step_goal_row"))
        XCTAssertTrue(identifiers.contains("settings_daily_weigh_in_reminder_toggle"))
        XCTAssertTrue(identifiers.contains("settings_daily_weigh_in_reminder_time_picker"))
        XCTAssertTrue(identifiers.contains("settings_subscription_status_row"))
        XCTAssertTrue(identifiers.contains("settings_manage_subscription_button"))
        XCTAssertTrue(identifiers.contains("settings_restore_purchases_button"))
        XCTAssertTrue(identifiers.contains("settings_goal_editor_sheet"))
        XCTAssertTrue(identifiers.contains("settings_goal_editor_text_field"))
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
    }
}
