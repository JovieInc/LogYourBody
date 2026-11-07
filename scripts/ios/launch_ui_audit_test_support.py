"""Shared real-source fixtures for the launch UI audit behavior suite."""

import contextlib
import importlib.util
import io
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
# The coverage tracer counts every Python line. Copying the Swift tree in
# this process pushes the required suite past its 30s limit.
_COPY_APP_SWIFT_TREE = """
import shutil
import sys
from pathlib import Path
root, dest = (Path(arg) for arg in sys.argv[1:])
for source in (root / "apps/ios/LogYourBody").rglob("*.swift"):
    target = dest / source.relative_to(root)
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
"""
SPEC = importlib.util.spec_from_file_location(
    "launch_ui_audit", ROOT / "scripts/ios/launch-ui-regression-audit.py"
)
AUDIT = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = AUDIT
SPEC.loader.exec_module(AUDIT)
from launch_ui_home_interaction_audit import _balanced_end  # noqa: E402


class BraceScannerTests(unittest.TestCase):
    def test_brace_scanner_preserves_strings_comments_and_unclosed_input(self):
        cases = [
            ('prefix { nested { value } }', 7, ' suffix'),
            (r'{ "escaped \" }" { value } }', 0, ' suffix'),
            ('{ // } ignored\n /* { ignored } */ { value } }', 0, ' suffix'),
            ('{ "unterminated }', 0, ''),
            ('{ /* unterminated }', 0, ''),
            ('{ // unterminated }', 0, ''),
        ]
        for source, start, suffix in cases:
            with self.subTest(source=source):
                self.assertEqual(_balanced_end(source + suffix, start), len(source) - 1)

    def test_brace_scanner_traces_tokens_instead_of_source_characters(self):
        # Keep coverage cost bounded without a wall-clock benchmark or a larger CI timeout.
        source = '{' + ' ' * 20_000 + '"' + '}' * 20_000 + '" /* { */ // }\n}'
        events = 0

        def count_lines(frame, event, _argument):
            nonlocal events
            if event == 'line' and frame.f_code is _balanced_end.__code__:
                events += 1
            return count_lines

        previous = sys.gettrace()
        try:
            sys.settrace(count_lines)
            end = _balanced_end(source, 0)
        finally:
            sys.settrace(previous)
        self.assertEqual(end, len(source) - 1)
        self.assertLess(events, 100, 'Brace scanning must trace tokens, not source characters')


class LaunchUIAuditTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls._swift_template = tempfile.TemporaryDirectory()
        subprocess.run(
            [sys.executable, "-c", _COPY_APP_SWIFT_TREE, str(ROOT), cls._swift_template.name],
            check=True,
        )

    @classmethod
    def tearDownClass(cls):
        cls._swift_template.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.app = self.root / "apps/ios/LogYourBody"
        subprocess.run(
            ["cp", "-a", str(Path(self._swift_template.name) / "apps"), str(self.root)],
            check=True,
        )

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
