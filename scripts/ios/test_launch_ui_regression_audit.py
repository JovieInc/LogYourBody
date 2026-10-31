#!/usr/bin/env python3
"""Exercise the real launch audit against mutated copies of the Swift sources."""

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import shutil
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location(
    "launch_ui_audit", ROOT / "scripts/ios/launch-ui-regression-audit.py"
)
AUDIT = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = AUDIT
SPEC.loader.exec_module(AUDIT)


class StatsCardCompositionTests(unittest.TestCase):
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

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / "apps/ios/LogYourBody"
        for source in (ROOT / "apps/ios/LogYourBody").rglob("*.swift"):
            target = self.root / source.relative_to(ROOT)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, target)

    def replace(self, relative_path, before, after):
        path = self.app / relative_path
        source = path.read_text()
        self.assertIn(before, source)
        path.write_text(source.replace(before, after))

    def run_audit(self):
        output = self.root / "audit-output"
        with patch.object(sys, "argv", ["audit", "--root", str(self.root), "--artifact-dir", str(output)]):
            with contextlib.redirect_stdout(io.StringIO()):
                result = AUDIT.main()
        return result, output

    def assert_rejected(self, check):
        result, output = self.run_audit()
        self.assertEqual(result, 1)
        self.assertIn(check, "\n".join(path.read_text() for path in output.glob("*.json")))

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


def run_behavior_suite(suite):
    expected = suite.countTestCases()
    result = unittest.TextTestRunner().run(suite)
    print(f"Launch UI audit behavior tests executed: {result.testsRun}/{expected}")
    complete = expected > 0 and result.testsRun == expected and not result.skipped
    return 0 if complete and result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(run_behavior_suite(unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])))
