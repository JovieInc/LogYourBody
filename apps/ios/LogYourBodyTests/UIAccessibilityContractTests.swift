//
// UIAccessibilityContractTests.swift
// LogYourBodyTests
//
// Locks the XCUI / world-class screen contract that UI refactors must keep.
// Found by the iOS UI refactor self-verification loop.
//
import XCTest
@testable import LogYourBody

final class UIAccessibilityContractTests: XCTestCase {
    func testWorldClassScreenCatalogStaysCompleteAndStable() {
        XCTAssertEqual(WorldClassScreen.allCases.count, 46)

        let identifiers = WorldClassScreen.allCases.map(\.accessibilityIdentifier)
        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        XCTAssertTrue(identifiers.allSatisfy { $0.hasPrefix("world_class_screen_") })

        XCTAssertEqual(WorldClassScreen.settings.accessibilityIdentifier, "world_class_screen_settings")
        XCTAssertEqual(WorldClassScreen.signIn.accessibilityIdentifier, "world_class_screen_signIn")
        XCTAssertEqual(WorldClassScreen.home.accessibilityIdentifier, "world_class_screen_home")
        XCTAssertEqual(WorldClassScreen.photoTimeline.accessibilityIdentifier, "world_class_screen_photoTimeline")
        XCTAssertEqual(WorldClassScreen.paywall.accessibilityIdentifier, "world_class_screen_paywall")
        XCTAssertEqual(WorldClassScreen.metricDetail.accessibilityIdentifier, "world_class_screen_metricDetail")
        XCTAssertEqual(WorldClassScreen.editProfile.accessibilityIdentifier, "world_class_screen_editProfile")
        XCTAssertEqual(WorldClassScreen.importPhotos.accessibilityIdentifier, "world_class_screen_importPhotos")
    }

    func testJovieTokensStayAtomicAndTouchSized() {
        XCTAssertEqual(JovieTokens.screenInset, 20)
        XCTAssertEqual(JovieTokens.compactInset, 16)
        XCTAssertEqual(JovieTokens.minimumHitTarget, 44)
        XCTAssertEqual(JovieTokens.compactControlHeight, 44)
        XCTAssertEqual(JovieTokens.controlHeight, 52)
        XCTAssertEqual(JovieTokens.cardRadius, 20)
        XCTAssertEqual(JovieTokens.controlRadius, 16)
        XCTAssertGreaterThanOrEqual(JovieTokens.controlHeight, JovieTokens.minimumHitTarget)
    }

    func testRequiredUITestIdentifiersStayDeclared() {
        let required = UIAccessibilityContract.requiredSourceIdentifiers
        XCTAssertGreaterThanOrEqual(required.count, 40)
        XCTAssertEqual(Set(required).count, required.count, "Identifier contract contains duplicates")
        XCTAssertTrue(required.contains("settings_profile_link"))
        XCTAssertTrue(required.contains("continueWithAppleButton"))
        XCTAssertTrue(required.contains("launch_timeline_surface"))
        XCTAssertTrue(required.contains("paywall_purchase_button"))
        XCTAssertTrue(required.contains(WorldClassScreen.signIn.accessibilityIdentifier))
        XCTAssertTrue(required.contains(WorldClassScreen.home.accessibilityIdentifier))
        XCTAssertTrue(required.contains(WorldClassScreen.settings.accessibilityIdentifier))
        XCTAssertTrue(required.contains(WorldClassScreen.paywall.accessibilityIdentifier))
        XCTAssertTrue(required.contains(WorldClassScreen.bodyScoreIntro.accessibilityIdentifier))
        XCTAssertTrue(required.contains(WorldClassScreen.dailyReminder.accessibilityIdentifier))
        XCTAssertEqual(
            "settings_\(PreferenceGoalKind.weight.rawValue)_goal_edit_button",
            "settings_weight_goal_edit_button"
        )
    }
}

enum UIAccessibilityContract {
    /// Identifiers XCUI tests tap. `scripts/ios/verify-ui.sh` greps the app
    /// target so a visual refactor cannot silently rename them.
    static let requiredSourceIdentifiers = [
        "continueWithAppleButton",
        "mvp_weight_text_field",
        "mvp_keyboard_save_weight_bar_button",
        "mvp_weight_saved_message",
        "mvp_weight_validation_message",
        "mvp_settings_button",
        "paywall_title",
        "paywall_plans_unavailable_state",
        "paywall_contact_support_button",
        "paywall_retry_offerings_button",
        "paywall_restore_purchases_button",
        "paywall_logout_button",
        "paywall_purchase_button",
        "settings_profile_link",
        "settings_logout_button",
        "settings_account_subscription_link",
        "settings_manage_subscription_button",
        "settings_restore_purchases_button",
        "settings_tracking_link",
        "settings_weight_goal_edit_button",
        "settings_goal_editor_text_field",
        "settings_goal_editor_error",
        "settings_weight_goal_reset_button",
        "settings_profile_height_row",
        "settings_integrations_link",
        "profile_editor_cancel_button",
        "profile_height_editor",
        "launch_timeline_surface",
        "launch_timeline_scrubber",
        "photo_timeline_root_page_timeline",
        "photo_timeline_root_page_analytics",
        "photo_timeline_stats_presence_summary",
        "photo_timeline_stats_metric_stack",
        "photo_timeline_stats_metric_card_weight",
        "photo_timeline_stats_metric_card_body_fat",
        "photo_timeline_stats_metric_card_ffmi",
        "dashboard_home_timeline_hero",
        "dashboard_home_quick_answer",
        "metric_detail_headline",
        "metric_detail_chart",
        "chat_tab_root",
        "home_chat_composer_dock",
        "chat_composer",
        "chat_composer_shell",
        "chat_send_button",
        "chat_retry_button",
        "body_score_onboarding_start_button",
        "body_score_onboarding_basics_continue_button",
        "body_score_onboarding_height_continue_button",
        "body_score_onboarding_enter_manually_button",
        "body_score_onboarding_manual_weight_continue_button",
        "body_score_hero_share_button",
        "body_score_share_sheet",
        "body_score_share_card",
        "body_score_share_close_button",
        "photo_timeline_hud_phase_insight",
        "photo_timeline_hud_glp1_weekly_checkin",
        "integrations_bulk_photo_import_link",
        "world_class_screen_signIn",
        "world_class_screen_home",
        "world_class_screen_settings",
        "world_class_screen_paywall",
        "world_class_screen_bodyScoreIntro",
        "world_class_screen_dailyReminder"
    ]
}
