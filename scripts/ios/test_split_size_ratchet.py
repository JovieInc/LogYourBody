"""The company 500-line guard rejects new Swift files. This ratchet splits them."""
import importlib.util
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location(
    "split_size_ratchet", Path(__file__).with_name("split_size_ratchet.py")
)
ratchet = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ratchet)

OWNED = (
    "apps/ios/LogYourBody/Services/BodyVisualizationSnapshot.swift",
    "apps/ios/LogYourBody/Services/BodyVisualizationComposer.swift",
    "apps/ios/LogYourBodyTests/BodyVisualizationSnapshotTests.swift",
    "apps/ios/LogYourBodyTests/BodyVisualizationSnapshotFixtures.swift",
)


def _types(count):
    blocks = []
    for index in range(count):
        blocks.append(
            "enum Type%d {\n    let raw = #\"brace { still %d\"#\n    func keep() { _ = 1 }\n}\n"
            % (index, index)
        )
    return "import Foundation\n\n" + "\n".join(blocks)


class SplitSizeRatchetTests(unittest.TestCase):
    def test_pack_keeps_each_type_intact_and_under_the_limit(self):
        source = _types(6)
        self.assertGreater(ratchet.line_count(source), 12)
        bodies = ratchet.pack(source, 12)
        self.assertGreater(len(bodies), 1)
        for body in bodies:
            self.assertLessEqual(ratchet.line_count(body), 12)
            self.assertIn('let raw = #"brace { still', body)
        restored = "\n".join(
            line for body in bodies for line in body.splitlines()
            if line.startswith("enum Type") or line.startswith("    ")
        )
        original = "\n".join(
            line for line in source.splitlines()
            if line.startswith("enum Type") or line.startswith("    ")
        )
        self.assertEqual(restored, original)
        self.assertTrue(bodies[0].startswith("import Foundation\n"))
        self.assertTrue(bodies[1].startswith("import Foundation\n"))

    def test_single_type_over_the_limit_is_refused(self):
        fields = "\n".join("    let value%d = %d" % (index, index) for index in range(40))
        source = "import Foundation\n\nstruct Only {\n%s\n}\n" % fields
        with self.assertRaises(ValueError) as caught:
            ratchet.pack(source, 10)
        self.assertIn("extract part of that type by hand", str(caught.exception))

    def test_apply_writes_siblings_and_refuses_to_overwrite(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "Sample.swift"
            original = _types(6)
            source.write_text(original)
            paths = ratchet.apply_split(source, 12)
            self.assertEqual(paths[0], source)
            self.assertTrue(all(path.is_file() for path in paths))
            self.assertLessEqual(ratchet.line_count(source.read_text()), 12)
            source.write_text(original)
            with self.assertRaises(ValueError):
                ratchet.apply_split(source, 12)

    def test_visualization_sources_fit_the_company_size_guard(self):
        for relative in OWNED:
            text = (ROOT / relative).read_text()
            self.assertLessEqual(
                ratchet.line_count(text),
                ratchet.LIMIT,
                relative + " exceeds the company size guard; run scripts/ios/split_size_ratchet.py",
            )
        snapshot = (ROOT / OWNED[0]).read_text()
        composer = (ROOT / OWNED[1]).read_text()
        self.assertEqual(snapshot.count("enum CodingKeys"), 2)
        self.assertIn("enum BodyVisualizationComposer", composer)
        self.assertNotIn("enum BodyVisualizationComposer", snapshot)


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(SplitSizeRatchetTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(0 if result.wasSuccessful() else 1)
