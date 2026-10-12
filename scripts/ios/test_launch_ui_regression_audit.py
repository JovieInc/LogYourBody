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


if __name__ == "__main__":
    result = unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(StatsCardCompositionTests))
    print(f"Launch UI audit behavior tests executed: {result.testsRun}")
    sys.exit(0 if result.wasSuccessful() else 1)
