"""Exercise the launch gate's scanner and shrink-only baseline through its CLI."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('optical_grid', Path(__file__).with_name('optical-grid-audit.py'))
grid = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = grid
spec.loader.exec_module(grid)


class OpticalGridTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.source = self.root / grid.SOURCE_ROOT / 'View.swift'
        self.source.parent.mkdir(parents=True)
        self.baseline = self.root / 'baseline.json'
        self.artifacts = self.root / 'artifacts'

    def run_audit(self, *extra):
        args = ['audit', '--root', str(self.root), '--baseline', str(self.baseline),
                '--artifact-dir', str(self.artifacts), *extra]
        with patch.object(sys, 'argv', args), contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return grid.main()

    def test_new_file_drift_fails_and_emits_all_detector_receipts(self):
        self.source.write_text('VStack(spacing: 7)\n.padding(3)\n.cornerRadius(7)\nColor(hex: "#FFFFFF")\nColor.red\n.font(.system(size: 28, weight: .bold))\n')
        self.assertEqual(self.run_audit(), 1)
        report = json.loads((self.artifacts / 'optical-grid-audit.json').read_text())
        self.assertEqual(report['status'], 'failed')
        self.assertEqual(report['totals'], {'spacing_scale': 2, 'radius_scale': 1,
                         'raw_hex_color': 1, 'system_color': 1, 'display_weight': 1})
        self.assertEqual(len(report['regressions']), 5)
        self.assertIn('Regressions vs baseline: 5', (self.artifacts / 'optical-grid-audit.md').read_text())

    def test_allowed_scales_comments_and_palette_definitions_pass(self):
        self.source.write_text('// .padding(7) Color.red\n.padding(0)\n.padding(1)\n.padding(2)\n.padding(.top, 16)\n.cornerRadius(14)\n.cornerRadius(999)\n.cornerRadius(8)\n')
        palette = self.root / 'apps/ios/LogYourBody/DesignSystem/Theme.swift'
        palette.parent.mkdir(parents=True)
        palette.write_text('Color.red\nColor(hex: "#FFFFFF")\n')
        self.assertEqual(self.run_audit(), 0)

    def test_baseline_can_be_initialized_and_shrunk(self):
        self.source.write_text('.padding(7)\n.padding(3)\n')
        self.assertEqual(self.run_audit('--update-baseline'), 0)
        self.assertEqual(self.run_audit(), 0)
        self.source.write_text('.padding(4)\n')
        self.assertEqual(self.run_audit('--update-baseline'), 0)
        self.assertEqual(json.loads(self.baseline.read_text())['counts'], {})

    def test_existing_zero_baseline_cannot_grow(self):
        self.baseline.write_text('{"schemaVersion": 1, "counts": {}}\n')
        original = self.baseline.read_bytes()
        self.source.write_text('.padding(7)\n')
        self.assertEqual(self.run_audit('--update-baseline'), 2)
        self.assertEqual(self.baseline.read_bytes(), original)

    def test_growth_cannot_be_hidden_by_improvement_in_another_file(self):
        self.source.write_text('.padding(7)\n.padding(3)\n')
        self.assertEqual(self.run_audit('--update-baseline'), 0)
        original = self.baseline.read_bytes()
        self.source.write_text('.padding(4)\n')
        self.source.with_name('NewView.swift').write_text('.padding(7)\n')
        self.assertEqual(self.run_audit('--update-baseline'), 2)
        self.assertEqual(self.baseline.read_bytes(), original)

    def test_empty_existing_baseline_fails_closed(self):
        self.baseline.write_text('')
        self.source.write_text('.padding(7)\n')
        self.assertEqual(self.run_audit('--update-baseline'), 2)
        self.assertEqual(self.run_audit(), 1)

    def test_color_component_access_is_not_a_semantic_color_violation(self):
        self.source.write_text('let red = components.red\ncase .red:\nUIColor.red\n')
        self.assertEqual(self.run_audit(), 0)
        self.assertEqual(json.loads((self.artifacts / 'optical-grid-audit.json').read_text())['status'], 'passed')


if __name__ == '__main__':
    result = unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(OpticalGridTests))
    print(f'Optical grid behavior tests executed: {result.testsRun}')
    if not result.wasSuccessful() or result.testsRun == 0:
        sys.exit(1)
