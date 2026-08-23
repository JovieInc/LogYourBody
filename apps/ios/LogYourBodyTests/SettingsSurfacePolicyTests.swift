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
        XCTAssertTrue(identifiers.contains("settings_profile_name_row"))
        XCTAssertTrue(identifiers.contains("settings_profile_date_of_birth_row"))
        XCTAssertTrue(identifiers.contains("settings_profile_height_row"))
        XCTAssertTrue(identifiers.contains("profile_name_editor"))
        XCTAssertTrue(identifiers.contains("profile_date_of_birth_editor"))
        XCTAssertTrue(identifiers.contains("profile_height_editor"))
        XCTAssertTrue(identifiers.contains("profile_editor_cancel_button"))
        XCTAssertTrue(identifiers.contains("world_class_screen_editProfile"))
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

    func testEditProfileSheetsUseTheAccountWorldClassScreen() {
        XCTAssertEqual(SettingsSurfacePolicy.editProfileScreen, .editProfile)
        XCTAssertEqual(WorldClassScreen.editProfile.flow, .account)
        XCTAssertEqual(
            SettingsSurfacePolicy.editProfileScreen.accessibilityIdentifier,
            "world_class_screen_editProfile"
        )
    }

    func testEditProfileSheetsExposeStableAccessibilityIdentifiers() {
        let identifiers = SettingsSurfacePolicy.profileEditorAccessibilityIdentifiers

        XCTAssertEqual(
            identifiers,
            [
                "world_class_screen_editProfile",
                "profile_name_editor",
                "profile_date_of_birth_editor",
                "profile_height_editor",
                "profile_editor_cancel_button"
            ]
        )
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        XCTAssertTrue(identifiers.contains(WorldClassScreen.editProfile.accessibilityIdentifier))
        XCTAssertTrue(
            SettingsSurfacePolicy.nestedAccessibilityIdentifiers
                .contains(WorldClassScreen.editProfile.accessibilityIdentifier)
        )
    }
}
