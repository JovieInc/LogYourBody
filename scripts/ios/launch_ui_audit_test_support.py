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
