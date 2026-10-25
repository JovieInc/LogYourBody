//
// UIAccessibilityContractTests.swift
// LogYourBodyTests
//
// Locks the XCUI / world-class screen contract that UI refactors must keep.
// Found by the iOS UI refactor self-verification loop.
//
import XCTest
import SwiftUI
import Vision
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
        XCTAssertTrue(required.contains("settings_profile_name_row"))
        XCTAssertTrue(required.contains("settings_profile_date_of_birth_row"))
        XCTAssertTrue(required.contains("profile_name_editor"))
        XCTAssertTrue(required.contains("profile_date_of_birth_editor"))
        XCTAssertTrue(required.contains("profile_height_editor"))
        XCTAssertTrue(required.contains("profile_editor_cancel_button"))
        XCTAssertTrue(required.contains(WorldClassScreen.editProfile.accessibilityIdentifier))
        XCTAssertTrue(required.contains("continueWithAppleButton"))
        XCTAssertTrue(required.contains("launch_timeline_surface"))
        XCTAssertTrue(required.contains("paywall_purchase_button"))
        XCTAssertTrue(required.contains(WorldClassScreen.signIn.accessibilityIdentifier))
        XCTAssertTrue(required.contains(WorldClassScreen.home.accessibilityIdentifier))
        XCTAssertTrue(required.contains(WorldClassScreen.photoTimeline.accessibilityIdentifier))
        XCTAssertTrue(required.contains(WorldClassScreen.settings.accessibilityIdentifier))
        XCTAssertTrue(required.contains(WorldClassScreen.paywall.accessibilityIdentifier))
        XCTAssertTrue(required.contains(WorldClassScreen.bodyScoreIntro.accessibilityIdentifier))
        XCTAssertTrue(required.contains(WorldClassScreen.dailyReminder.accessibilityIdentifier))
        XCTAssertTrue(required.contains("home_v2_paywall"))
        XCTAssertTrue(required.contains("home_v2_paywall_restore"))
        XCTAssertTrue(required.contains("home_v2_paywall_log_out"))
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
        "home_v2_paywall",
        "home_v2_paywall_status",
        "home_v2_paywall_purchase",
        "home_v2_paywall_restore",
        "home_v2_paywall_log_out",
        "home_v2_paywall_plans_unavailable",
        "home_v2_paywall_plan_",
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
        "settings_profile_name_row",
        "settings_profile_date_of_birth_row",
        "settings_integrations_link",
        "profile_editor_cancel_button",
        "profile_name_editor",
        "profile_date_of_birth_editor",
        "profile_height_editor",
        "world_class_screen_editProfile",
        "launch_timeline_surface",
        "launch_timeline_scrubber",
        "photo_timeline_root_page_timeline",
        "photo_timeline_root_page_analytics",
        "photo_timeline_root_menu",
        "photo_timeline_menu",
        "home_chat_collapse",
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
        "world_class_screen_photoTimeline",
        "world_class_screen_settings",
        "world_class_screen_paywall",
        "world_class_screen_bodyScoreIntro",
        "world_class_screen_dailyReminder"
    ]
}

extension UIAccessibilityContractTests {
    @MainActor
    func testMetricActionRolloutRequiresItsSpecificGate() {
        XCTAssertFalse(MetricCardActionPolicy.isEnabled { _ in false })
        XCTAssertTrue(MetricCardActionPolicy.isEnabled {
            [MetricCardIdentityPolicy.gateKey, "metric_card_actions_v1"].contains($0)
        })
        XCTAssertFalse(MetricCardActionPolicy.isEnabled { $0 == "metric_card_actions_v1" })
        XCTAssertFalse(MetricCardActionPolicy.isEnabled { $0 == MetricCardIdentityPolicy.gateKey })
    }

    @MainActor
    func testEveryMetricStateHasOneTruthfulActionAndLoadingHasNone() {
        for title in ["Steps", "Weight", "Body Fat", "FFMI"] {
            var detailCalls = 0
            var stateCalls = 0
            let detail = MetricSummaryCard.CardAction(title: "Show details") { detailCalls += 1 }
            let action = MetricSummaryCard.CardAction(title: "Review Health access", hint: "Shows Health access details") {
                stateCalls += 1
            }
            for state: MetricSummaryCard.State in [
                .empty(title: title, message: "Health access needed", action: action),
                .error(title: title, message: "Unable to load", action: action)
            ] {
                let card = MetricSummaryCard(icon: "circle", accentColor: .blue, state: state, detailAction: detail)
                XCTAssertEqual(card.primaryAction(actionsEnabled: true)?.title, "Review Health access")
                XCTAssertEqual(card.actionHint(actionsEnabled: true), "Shows Health access details")
                card.primaryAction(actionsEnabled: true)?.handler()
                XCTAssertEqual(detailCalls, 0, "The state action must take precedence over navigation")
                XCTAssertNil(card.primaryAction(actionsEnabled: false), "Rollback must not nest state/navigation buttons")
            }
            XCTAssertEqual(stateCalls, 2, "One invocation per activation")
            let loading = MetricSummaryCard(
                icon: "circle", accentColor: .blue, state: .loading(title: title), detailAction: detail
            )
            for enabled in [false, true] {
                XCTAssertNil(loading.primaryAction(actionsEnabled: enabled))
                XCTAssertNil(loading.actionHint(actionsEnabled: enabled))
            }
            let unavailable = MetricSummaryCard(
                icon: "circle", accentColor: .blue,
                state: .error(title: title, message: "Unavailable", action: nil)
            )
            XCTAssertNil(unavailable.primaryAction(actionsEnabled: true))
            XCTAssertNil(unavailable.actionHint(actionsEnabled: true))
        }
    }

    func testMetricTrendAccessibilityPreservesEveryDisplayedPeriodWithoutRepeatingNoChange() {
        for period in ["7d", "1M", "3M", "6M", "1Y", "All"] {
            let trend = MetricSummaryCard.Trend(direction: .flat, valueText: "No change", caption: period)
            XCTAssertEqual(trend.accessibilityDescription, "No change, \(period)")
        }
    }

    func testMetricTrendAccessibilityPreservesDirectionValueAndPeriod() {
        let increasing = MetricSummaryCard.Trend(direction: .up, valueText: "1.2 lb", caption: "7d")
        let decreasing = MetricSummaryCard.Trend(direction: .down, valueText: "0.4%", caption: "1M")
        XCTAssertEqual(increasing.accessibilityDescription, "Up 1.2 lb, 7d")
        XCTAssertEqual(decreasing.accessibilityDescription, "Down 0.4%, 1M")
    }

    func testMetricTrendAccessibilityDoesNotInventAnAbsentPeriod() {
        let noPeriod = MetricSummaryCard.Trend(direction: .flat, valueText: "No change")
        let emptyPeriod = MetricSummaryCard.Trend(direction: .up, valueText: "2", caption: "")
        let customPeriod = MetricSummaryCard.Trend(direction: .down, valueText: "1", caption: "vs last week")
        XCTAssertEqual(noPeriod.accessibilityDescription, "No change")
        XCTAssertEqual(emptyPeriod.accessibilityDescription, "Up 2")
        XCTAssertEqual(customPeriod.accessibilityDescription, "Down 1, vs last week")
    }

    func testMetricTrendAccessibilityRetainsNumericFlatValueFromLegacyCallers() {
        let trend = MetricSummaryCard.Trend(direction: .flat, valueText: "0.0")
        XCTAssertEqual(trend.accessibilityDescription, "No change 0.0")
    }
}

extension UIAccessibilityContractTests {
    @MainActor
    func testMetricIdentitySurvivesLoadingEmptyAndErrorStates() {
        for title in ["Steps", "Weight", "Body fat", "FFMI"] {
            let states: [(MetricSummaryCard.State, String)] = [
                (.loading(title: title), "Loading \(title)"),
                (.empty(title: title, message: "No data", action: nil), "\(title), No data"),
                (.error(title: title, message: "Unable to load", action: nil), "\(title), Unable to load")
            ]
            for (state, expected) in states {
                let card = MetricSummaryCard(icon: "circle", accentColor: .blue, state: state)
                XCTAssertEqual(card.titleText(identityEnabled: true), title)
                XCTAssertEqual(card.accessibilityLabel(identityEnabled: true), expected)
                XCTAssertEqual(card.titleText(identityEnabled: false), "Metric")
            }
        }
    }

    @MainActor
    func testMetricAccessibleSummaryRetainsHiddenChartAndSourceContext() {
        let content = MetricSummaryCard.Content(
            title: "Weight", value: "80.0", unit: "kg", timestamp: "Today",
            dataPoints: [], chartAccessibilityLabel: "Recorded weight, last 30 days",
            chartAccessibilityValue: "12 recorded entries",
            trend: .init(direction: .flat, valueText: "No change", caption: "1M"),
            footnote: "Apple Health"
        )
        let card = MetricSummaryCard(icon: "circle", accentColor: .blue, state: .data(content))
        XCTAssertEqual(card.accessibilityLabel(identityEnabled: true),
                       "Weight, 80.0 kg, No change, 1M, Updated Today, " +
                        "Recorded weight, last 30 days, 12 recorded entries, Apple Health")
        XCTAssertEqual(card.accessibilityLabel(identityEnabled: false),
                       "Weight, 80.0 kg, No change, 1M, Updated Today")
    }

    @MainActor
    func testMetricIdentityRolloutRequiresItsSpecificGate() {
        XCTAssertFalse(MetricCardIdentityPolicy.isEnabled { _ in false })
        XCTAssertTrue(MetricCardIdentityPolicy.isEnabled { $0 == "metric_card_identity_v1" })
        XCTAssertFalse(MetricCardIdentityPolicy.isEnabled { $0 == "some_other_gate" })
    }

    @MainActor
    func testRenderedMetricStatesKeepTheirVisibleName() throws {
        let states: [(String, MetricSummaryCard.State)] = [
            ("loading", .loading(title: "Body fat")),
            ("empty", .empty(title: "Body fat", message: "No measurements yet", action: nil)),
            ("error", .error(title: "Body fat", message: "Unable to load measurements", action: nil))
        ]
        for enabled in [false, true] {
            for size: DynamicTypeSize in [.large, .accessibility3] {
                for (name, state) in states {
                    let card = MetricSummaryCard(icon: "percent", accentColor: .blue, state: state)
                        .environment(\.metricCardIdentity, enabled)
                        .environment(\.metricCardActions, false)
                        .environment(\.dynamicTypeSize, size)
                        .transaction { $0.animation = nil; $0.disablesAnimations = true }
                        .padding(20)
                        .background(Color.appBackground)
                        .preferredColorScheme(.dark)
                    let renderer = ImageRenderer(content: card)
                    renderer.proposedSize = ProposedViewSize(width: 320, height: nil)
                    renderer.scale = 2
                    let image = try XCTUnwrap(renderer.uiImage)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "metric-identity-\(enabled)-\(name)-\(size)"
                    attachment.lifetime = .keepAlways
                    add(attachment)
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.recognitionLanguages = ["en-US"]
                    try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage), options: [:]).perform([request])
                    let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                        .joined(separator: " ")
                    XCTAssertTrue(text.contains(enabled ? "Body fat" : "Metric"), text)
                }
            }
        }
    }
}
