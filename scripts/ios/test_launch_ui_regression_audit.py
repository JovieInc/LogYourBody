#!/usr/bin/env python3
"""Exercise the real launch audit against mutated copies of the Swift sources."""

import contextlib
import importlib.util
import io
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


if __name__ == "__main__":
    result = unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(StatsCardCompositionTests))
    print(f"Launch UI audit behavior tests executed: {result.testsRun}")
    sys.exit(0 if result.wasSuccessful() else 1)
