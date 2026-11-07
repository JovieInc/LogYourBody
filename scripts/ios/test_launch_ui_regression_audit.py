#!/usr/bin/env python3
"""Exercise the real launch audit against mutated copies of the Swift sources."""

import contextlib
import io
import json
from pathlib import Path
import shutil
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from launch_ui_audit_test_support import AUDIT, ROOT, LaunchUIAuditTests  # noqa: E402


class StatsCardCompositionTests(LaunchUIAuditTests):
    def test_behavior_runner_requires_complete_unskipped_execution(self):
        class IncompleteSuite(unittest.TestSuite):
            def countTestCases(self):
                return 2

        def passing():
            pass

        def failing():
            self.fail("behavior regression")

        cases = [
            ("complete", unittest.TestSuite([unittest.FunctionTestCase(passing)]), 0),
            ("empty", unittest.TestSuite(), 1),
            ("failed", unittest.TestSuite([unittest.FunctionTestCase(failing)]), 1),
            ("skipped", unittest.TestSuite([
                unittest.FunctionTestCase(unittest.skip("missing evidence")(passing))
            ]), 1),
            ("incomplete", IncompleteSuite([unittest.FunctionTestCase(passing)]), 1),
        ]
        for name, suite, expected in cases:
            with self.subTest(name=name), contextlib.redirect_stdout(io.StringIO()), \
                    contextlib.redirect_stderr(io.StringIO()):
                self.assertEqual(run_behavior_suite(suite), expected)

    def test_empty_timeline_keeps_its_photo_button_accessible(self):
        findings = []
        AUDIT.check_timeline_calendar_day(self.root, findings, AUDIT.AuditViolation, AUDIT.line_number)
        self.assertEqual(findings, [])
        self.replace("Services/DatedTimelineUI.swift", ".accessibilityElement(children: .contain)", "")
        AUDIT.check_timeline_calendar_day(self.root, findings, AUDIT.AuditViolation, AUDIT.line_number)
        self.assertEqual([finding.check for finding in findings], ["timeline.empty_photo_accessibility"])

    def test_empty_timeline_requires_the_photo_action_identifier(self):
        self.replace("Services/DatedTimelineUI.swift", '"launch_timeline_add_photo"', '"wrong_photo_action"')
        findings = []
        AUDIT.check_timeline_calendar_day(self.root, findings, AUDIT.AuditViolation, AUDIT.line_number)
        self.assertEqual([finding.check for finding in findings], ["timeline.empty_photo_accessibility"])

    def test_geometry_requires_typed_nonfinite_arguments_in_every_native_tree(self):
        cases = [
            "CGPoint(x: .infinity, y: 0)",
            "CGPoint(x: 0, y: -.infinity)",
            "CGPoint(\n  x: 0,\n  y: .nan\n)",
            "CGSize(width: .nan, height: 1)",
            "CGSize(width: 1, height: +.infinity)",
            "CGRect(x: 0, y: 0, width: .infinity, height: 1)",
            "CGVector(dx: 0, dy: .nan)",
            "CGAffineTransform(a: 1, b: 0, c: .nan, d: 1, tx: 0, ty: 0)",
        ]
        expected = []
        # Audit all fixtures together; retain exact per-file findings under tracing.
        for directory in ("LogYourBody", "LogYourBodyTests", "LogYourBodyUITests", "LogYourBodyWidget"):
            for index, source in enumerate(cases):
                path = self.root / "apps/ios" / directory / f"GeometryFixture{index}.swift"
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(f"let invalid = {source}\n")
                expected.append(("swift.explicit_geometry_nonfinite", str(path.relative_to(self.root))))
        result, output = self.run_audit()
        self.assertEqual(result, 1)
        findings = json.loads((output / "launch-ui-regression-audit.json").read_text())["violations"]
        self.assertCountEqual([(finding["check"], finding["file"]) for finding in findings], expected)

    def test_geometry_allows_explicit_types_and_contextually_typed_constants(self):
        source = """
let point = CGPoint(x: CGFloat.infinity, y: -CGFloat.infinity)
let size = CGSize(width: Double.nan, height: 1)
let rect = CGRect(origin: .zero, size: CGSize(width: CGFloat.infinity, height: 1))
let transform = CGAffineTransform(translationX: 0, y: 1)
let scales: [CGFloat] = [0, -1, .infinity, .nan]
let registration = BodyPhotoRegistration(translation: .zero, rotation: .nan, scale: 1)
"""
        (self.app / "GeometryFixture.swift").write_text(source)
        self.assertEqual(self.run_audit()[0], 0)

    def test_stats_container_can_delegate_themed_cards(self):
        page = (self.app / "Views/DashboardViewLiquid+PhotoTimelineAnalytics.swift").read_text()
        self.assertNotIn(".dashboardContentSurface(", page)
        self.assertNotIn("Body trends", page)
        self.assertEqual(self.run_audit()[0], 0)

    def test_stats_must_keep_metric_content(self):
        self.replace("Views/DashboardViewLiquid+PhotoTimelineAnalytics.swift", "metricsView", "EmptyView()")
        self.assert_rejected("dashboard.stats_card_composition")

    def test_stats_must_keep_themed_canvas(self):
        self.replace("Views/DashboardViewLiquid+PhotoTimelineAnalytics.swift",
                     "theme.colors.background.ignoresSafeArea()", "Color.clear")
        self.assert_rejected("dashboard.stats_card_composition")

    def test_stats_must_reach_metric_section(self):
        self.replace("Views/DashboardViewLiquid+MetricViews.swift", "DashboardMetricsSection(", "OtherSection(")
        self.assert_rejected("dashboard.stats_card_composition")

    def test_metric_section_must_use_guarded_cards(self):
        self.replace("Views/DashboardMetricsSection.swift", "MetricSummaryCard(", "OtherCard(")
        self.assert_rejected("dashboard.stats_card_composition")

    def test_actual_metric_card_surface_remains_required(self):
        self.replace("DesignSystem/Organisms/MetricSummaryCard.swift",
                     ".background(theme.colors.surface", ".background(Color.clear")
        self.assert_rejected("dashboard.theme_backed_surface")

    def test_stats_still_rejects_legacy_colors(self):
        path = self.app / "Views/DashboardViewLiquid+PhotoTimelineAnalytics.swift"
        path.write_text(path.read_text() + "\nlet legacyColor = Color.white\n")
        self.assert_rejected("dashboard.system_b_theme_tokens")

    def test_launch_directive_requires_bounded_scroll_fallback(self):
        for before in [".frame(maxHeight: 160)", "ViewThatFits(in: .vertical)",
                       "ScrollView {\n                content"]:
            with self.subTest(before=before):
                path = self.app / "Services/LaunchJourneyUI.swift"
                source = path.read_text()
                self.replace("Services/LaunchJourneyUI.swift", before, "VStack { content }")
                self.assert_rejected("launch.bounded_scrollable_directive")
                path.write_text(source)

    def test_launch_directive_requires_feature_gate(self):
        self.replace("Views/DashboardViewLiquid+PhotoTimelineHUD.swift",
                     "if isLaunchJourneyEnabled {", "if true {")
        self.assert_rejected("launch.gated_directive")

    def test_launch_editor_cannot_wrap_home_provenance_presenters(self):
        modifier = ".sheet(isPresented: $showsLaunchOutcomeEditor) { launchJourneyOutcomeEditor }"
        self.replace("Services/LaunchJourneyUI.swift",
                     ".sheet(isPresented: $showsLaunchOutcomeEditor)", ".background")
        path = self.app / "Views/DashboardViewLiquid+PhotoTimelineHUD.swift"
        path.write_text(path.read_text() + "\n" + modifier + "\n")
        self.assert_rejected("launch.local_editor_presenter")

    def test_provenance_sheet_requires_presenting_binding(self):
        self.replace("Views/HomeV2/HomeV2MetricEditorial.swift", "@Binding var isPresented: Bool",
                     "var isPresented: Bool")
        self.assert_rejected("provenance.presenting_binding_dismissal")

    def test_provenance_done_cannot_use_ambient_dismiss(self):
        self.replace("Views/HomeV2/HomeV2MetricEditorial.swift",
                     "Button(action: { isPresented = false }, label: {",
                     "Button(action: { dismiss() }, label: {")
        self.assert_rejected("provenance.presenting_binding_dismissal")

    def test_progress_provenance_must_pass_its_presenting_binding(self):
        self.replace("Views/HomeV2/HomeV2MetricEditorial.swift",
                     "HomeV2ProvenanceSheet(detail: provenance, isPresented: $showsProvenance)",
                     "HomeV2ProvenanceSheet(detail: provenance, isPresented: .constant(true))")
        self.assert_rejected("provenance.presenting_binding_dismissal")

    def test_today_provenance_must_pass_its_presenting_binding(self):
        self.replace("Views/HomeV2/HomeV2Surface.swift",
                     "HomeV2ProvenanceSheet(detail: detail, isPresented: $showsProvenance)",
                     "HomeV2ProvenanceSheet(detail: detail, isPresented: .constant(true))")
        self.assert_rejected("provenance.presenting_binding_dismissal")
    def test_card_cannot_assign_success_to_direction_alone(self):
        self.replace("DesignSystem/Organisms/MetricSummaryCard.swift",
                     "return secondaryTextColor\n        }\n        switch direction",
                     "return theme.colors.success\n        }\n        switch direction")
        self.assert_rejected("dashboard.neutral_trend_direction")

    def test_detail_cannot_assign_success_to_direction_alone(self):
        self.replace("Components/FullMetricChartView+Part02.swift",
                     "return Color.metricTextSecondary\n        }",
                     "return Color.metricDeltaPositive\n        }")
        self.assert_rejected("dashboard.neutral_trend_direction")

    def test_observation_plot_cannot_erase_elapsed_time(self):
        self.replace("DesignSystem/Organisms/MetricSummaryCard.swift",
                     'PointMark(x: .value("Observation date", date)',
                     'PointMark(x: .value("Observation index", point.index)')
        self.assert_rejected("dashboard.observation_plot")

    def test_observation_plot_cannot_claim_continuous_measured_history(self):
        self.replace("DesignSystem/Organisms/MetricSummaryCard.swift",
                     'PointMark(x: .value("Observation date", date)',
                     'LineMark(x: .value("Observation date", date)')
        self.assert_rejected("dashboard.observation_plot")

    def test_single_timestamp_cannot_establish_no_change(self):
        self.replace("Helpers/DashboardMetricFormatting.swift",
                     "if requiresComparison && first.date == last.date { return nil }", "")
        self.assert_rejected("dashboard.minimum_comparison_samples")

    def test_chart_container_cannot_overwrite_plot_identity(self):
        self.replace("Components/FullMetricChartView+Part01.swift",
                     '.accessibilityElement(children: .contain)\n        .accessibilityIdentifier("metric_detail_chart")',
                     '.accessibilityIdentifier("metric_detail_chart")')
        self.assert_rejected("dashboard.chart_accessibility_containment")

    def test_chart_container_cannot_flatten_interactive_children(self):
        for behavior in ("ignore", "combine"):
            with self.subTest(behavior=behavior):
                path = self.app / "Components/FullMetricChartView+Part01.swift"
                source = path.read_text()
                self.replace("Components/FullMetricChartView+Part01.swift",
                             '.accessibilityElement(children: .contain)\n        .accessibilityIdentifier("metric_detail_chart")',
                             f'.accessibilityElement(children: .{behavior})\n        .accessibilityIdentifier("metric_detail_chart")')
                self.assert_rejected("dashboard.chart_accessibility_containment")
                path.write_text(source)

    def test_chart_containment_must_precede_identifier(self):
        self.replace("Components/FullMetricChartView+Part01.swift",
                     '.accessibilityElement(children: .contain)\n        .accessibilityIdentifier("metric_detail_chart")',
                     '.accessibilityIdentifier("metric_detail_chart")\n        .accessibilityElement(children: .contain)')
        self.assert_rejected("dashboard.chart_accessibility_containment")

    def test_checkin_card_cannot_lose_its_full_label_hit_region(self):
        path = self.app / "Views/DashboardViewLiquid+PhotoTimelineInsights.swift"
        source = path.read_text()
        start = source.index("    var hudGlp1WeeklyCheckIn:")
        end = source.index("    var isPhaseInsightEnabled:", start)
        card = source[start:end]
        # Run against the original source as well as the repaired card.
        card = card.replace(".contentShape(Rectangle())", "")
        path.write_text(source[:start] + card + source[end:])
        self.assert_rejected("dashboard.checkin_card_hit_region")

    def test_header_swipe_isolates_buttons_and_keeps_a_usable_title_region(self):
        self.assertEqual(self.run_audit()[0], 0)

    def test_header_container_cannot_observe_button_touches(self):
        path = self.app / "Views/DashboardViewLiquid+PhotoTimelineHUD.swift"
        source = path.read_text()
        for gesture in ("gesture", "simultaneousGesture", "highPriorityGesture"):
            for anchor in ("photoTimelineRootNavigation\n",
                           ".frame(maxWidth: .infinity, alignment: .leading)\n",
                           '.accessibilityIdentifier("photo_timeline_root_menu")\n'):
                with self.subTest(gesture=gesture, anchor=anchor):
                    self.assertIn(anchor, source)
                    # Reject parent/child interception even when the title retains its swipe.
                    mutated = source.replace(anchor, anchor + f"                .{gesture}(photoTimelineSwipe)\n", 1)
                    path.write_text(mutated)
                    self.assert_rejected("timeline.header_swipe_excludes_buttons")
                    path.write_text(source)

    def test_edge_swipe_cannot_share_the_menu_button(self):
        self.assertEqual(self.run_audit()[0], 0)
        path = self.app / "Views/DashboardViewLiquid+PhotoTimelineHUD.swift"
        source = path.read_text()
        start = source.index("                .overlay(alignment: .leading)")
        end = source.index("                .opacity(isHomeChatExpanded", start)
        overlay = source[start:end]
        detached = source[:start] + source[end:]
        parent = "        .fullScreenCover(isPresented: $isHomeV2ViewerPresented)"
        path.write_text(detached.replace(parent, overlay + parent, 1))
        self.assert_rejected("timeline.edge_swipe_excludes_header")
        path.write_text(source.replace(".frame(maxHeight: .infinity)\n                        .contentShape",
                                       ".padding(.top, 56)\n                        .contentShape", 1))
        self.assert_rejected("timeline.edge_swipe_excludes_header")

    def test_logout_actions_and_selection_reject_the_recorded_failure(self):
        ui_path = self.root / "apps/ios/LogYourBodyUITests/LogYourBodyUITests.swift"
        ui_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / ui_path.relative_to(self.root), ui_path)
        self.assertEqual(self.run_audit()[0], 0)
        settings = self.app / "Views/PreferencesView+Header.swift"
        source = settings.read_text()
        for identifier in ("settings_logout_confirm", "settings_logout_cancel"):
            token = '.accessibilityElement(children: .combine)'
            at = source.index(f'.accessibilityIdentifier("{identifier}")')
            start = source.rfind(token, 0, at)
            self.assertGreaterEqual(start, 0)
            settings.write_text(source[:start] + source[start:].replace(token, "", 1))
            self.assert_rejected("settings.logout_alert_one_element")
            settings.write_text(source)
        helper = ui_path.read_text()
        for token, replacement in (
            ('children(matching: .button).count == 0', 'descendants(matching: .button).firstMatch.exists'),
            ('seen.insert(key).inserted', 'true'),
            ('leaves.count == 1 ? leaves.first : nil', 'leaves.first'),
            ('$0.label == label', 'true'),
        ):
            self.assertIn(token, helper)
            ui_path.write_text(helper.replace(token, replacement, 1))
            self.assert_rejected("settings.logout_alert_action_selection")
            ui_path.write_text(helper)

    def test_segmentation_requires_a_serial_dispatch_worker(self):
        path = self.app / "Services/BackgroundRemovalService.swift"
        source = path.read_text()
        self.assertEqual(self.run_audit()[0], 0)
        for before, after in (
            ('segmentationQueue.async {', 'Task.detached {'),
            ('qos: .userInitiated\n    )', 'qos: .userInitiated, attributes: .concurrent\n    )'),
            ('continuation.resume(with: Result {', 'continuation.resume(with: Result { continuation.resume()'),
        ):
            self.assertIn(before, source)
            path.write_text(source.replace(before, after, 1))
            self.assert_rejected("photo.segmentation_dispatch_worker")
        path.write_text(source)

    def test_offline_fixture_must_precede_live_network_monitoring(self):
        path = self.app / "Services/RealtimeSyncManager.swift"
        source = path.read_text()
        self.assertEqual(self.run_audit()[0], 0)
        for before, after in (
            ('#if DEBUG\n        if arguments.contains(HomeV2SystemStatePolicy.offlineFixtureArgument)',
             'if arguments.contains(HomeV2SystemStatePolicy.offlineFixtureArgument)'),
            ('isOnline = false\n            syncStatus = .offline', 'isOnline = true'),
            ('syncStatus = .offline\n            return', 'syncStatus = .offline'),
            ('#if DEBUG\n        if arguments.contains(',
             'networkMonitor.start(queue: .global())\n        #if DEBUG\n        if arguments.contains('),
        ):
            with self.subTest(before=before):
                self.assertIn(before, source)
                path.write_text(source.replace(before, after, 1))
                self.assert_rejected("timeline.offline_fixture_network")
        path.write_text(source)

    def test_offline_retry_scenario_must_request_the_offline_fixture(self):
        path = self.root / "apps/ios/LogYourBodyUITests/LogYourBodyUITests+DatedTimeline.swift"
        path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / path.relative_to(self.root), path)
        self.assertEqual(self.run_audit()[0], 0)
        path.write_text(path.read_text().replace('"-lybUITestHomeV2OfflineFixture"', '"online"'))
        self.assert_rejected("timeline.offline_retry_fixture")

    def test_header_title_cannot_lose_navigation_or_its_hit_region(self):
        for token in (".gesture(photoTimelineSwipe)", ".contentShape(Rectangle())",
                      ", minHeight: JovieTokens.minimumHitTarget"):
            with self.subTest(token=token):
                path = self.app / "Views/DashboardViewLiquid+PhotoTimelineHUD.swift"
                source = path.read_text()
                path.write_text(source.replace(token, ""))
                self.assert_rejected("timeline.header_swipe_excludes_buttons")
                path.write_text(source)

    def test_checkin_hit_region_must_include_padding_inside_the_button_label(self):
        for before, after in (
            (".padding(16)\n            .contentShape(Rectangle())",
             ".contentShape(Rectangle())\n            .padding(16)"),
            (".contentShape(Rectangle())", ".contentShape(Circle())"),
        ):
            with self.subTest(replacement=after):
                path = self.app / "Views/DashboardViewLiquid+PhotoTimelineInsights.swift"
                source = path.read_text()
                self.replace("Views/DashboardViewLiquid+PhotoTimelineInsights.swift", before, after)
                self.assert_rejected("dashboard.checkin_card_hit_region")
                path.write_text(source)

    def test_every_size_ratchet_sibling_loads_or_the_audit_fails_closed(self):
        loaded = [
            AUDIT._load_sibling(module_name, filename, export)
            for module_name, filename, export in AUDIT._AUDIT_SIBLINGS
        ]
        self.assertEqual(
            [item[0] for item in AUDIT._AUDIT_SIBLINGS],
            [
                "launch_ui_timeline_day",
                "launch_ui_opacity_audit",
                "launch_ui_home_interaction_audit",
                "launch_ui_regression_report",
            ],
        )
        for export in loaded:
            self.assertTrue(callable(export))
        with self.assertRaises(RuntimeError) as missing_file:
            AUDIT._load_sibling("missing_sibling", "missing_launch_ui_sibling.py", "missing")
        self.assertIn("Cannot load launch UI audit sibling", str(missing_file.exception))
        with self.assertRaises(RuntimeError) as missing_export:
            AUDIT._load_sibling(
                "launch_ui_timeline_day", "launch_ui_timeline_day.py", "not_an_export",
            )
        self.assertIn("Cannot load launch UI audit sibling", str(missing_export.exception))

    def test_optional_cgfloat_opacity_must_be_explicit_double(self):
        policy = self.app / "Services/PersonMaskPolicy.swift"
        compare = self.app / "Views/HomeV2/HomeV2CompareView.swift"
        original_policy = policy.read_text()
        original_compare = compare.read_text()
        self.assertIn("var earlierOpacity: Double", original_policy)
        self.assertEqual(self.run_audit()[0], 0)

        policy.write_text(original_policy.replace(
            "var earlierOpacity: Double", "var earlierOpacity: CGFloat", 1
        ))
        self.assert_rejected("swift.optional_cgfloat_opacity")

        # A CGFloat member is allowed only after an explicit Double conversion.
        compare.write_text(original_compare.replace(
            ".opacity(blend?.earlierOpacity ?? 1)",
            ".opacity(Double(blend?.earlierOpacity ?? 1))",
            1,
        ))
        self.assertEqual(self.run_audit()[0], 0)
        policy.write_text(original_policy)
        compare.write_text(original_compare)

    def test_timeline_position_uses_the_injected_calendar_day(self):
        calculator = self.app / "Helpers/TimelineCalculator.swift"
        original = calculator.read_text()
        self.assertIn("now: Date = Date()", original)
        self.assertIn("if point.date >= thirtyDaysAgo {", original)
        tests = self.root / "apps/ios/LogYourBodyTests/TimelineCalculatorTests.swift"
        tests.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / "apps/ios/LogYourBodyTests/TimelineCalculatorTests.swift", tests)
        self.assertEqual(self.run_audit()[0], 0)

        tests.write_text("let date = now.addingTimeInterval(-daysAgo * 24 * 60 * 60)\n")
        self.assert_rejected("timeline.elapsed_day_offset")
        self.assert_rejected("timeline.fallback_hour_regression")

        tests.unlink()
        calculator.write_text(original.replace(
            "if point.date >= thirtyDaysAgo {",
            "if point.date >= thirtyDaysAgo {\n            let now = Date()",
            1,
        ))
        self.assert_rejected("timeline.injected_calendar_day")

        calculator.write_text(original.replace("now: Date = Date(),\n        ", "", 1))
        self.assert_rejected("timeline.injected_calendar_day")


    def test_character_typing_regains_focus_and_nested_launch_tests_get_time(self):
        ui = self.root / "apps/ios/LogYourBodyUITests"
        ui.mkdir(parents=True)
        shutil.copyfile(ROOT / "apps/ios/LogYourBodyUITests/LogYourBodyUITests.swift", ui / "LogYourBodyUITests.swift")
        shutil.copyfile(
            ROOT / "apps/ios/LogYourBodyUITests/ChaosMonkeyUITests.swift", ui / "ChaosMonkeyUITests.swift"
        )
        self.assertEqual(self.run_audit()[0], 0)

        chat = ui / "LogYourBodyUITests.swift"
        original = chat.read_text()
        focus = (
            '.matching(NSPredicate(format: "hasKeyboardFocus == true")).firstMatch\n'
            "                    if !focused.exists {\n"
            "                        if prefix.isEmpty {\n"
            "                            composer.tap()\n"
            "                        } else {\n"
            "                            composer.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()\n"
            "                        }\n"
            "                        guard focused.waitForExistence(timeout: 2) else { break }\n"
            "                    }\n"
            "                    "
        )
        self.assertIn(focus, original)
        chat.write_text(original.replace(focus, "", 1))
        self.assert_rejected("uitest.character_type_keyboard_focus")

        chat.write_text(original.replace(
            "        executionTimeAllowance = 180\n        let app = XCUIApplication()\n        launch(\n",
            "        let app = XCUIApplication()\n        launch(\n",
            1,
        ))
        self.assert_rejected("uitest.nested_launch_time_allowance")


def run_behavior_suite(suite):
    expected = suite.countTestCases()
    result = unittest.TextTestRunner().run(suite)
    print(f"Launch UI audit behavior tests executed: {result.testsRun}/{expected}")
    complete = expected > 0 and result.testsRun == expected and not result.skipped
    return 0 if complete and result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(run_behavior_suite(unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])))
