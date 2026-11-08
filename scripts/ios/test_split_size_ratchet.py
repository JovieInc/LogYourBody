"""The company 500-line guard rejects new Swift files. This ratchet splits them."""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
import split_size_ratchet as ratchet
from split_size_ratchet import (
    apply_split, argument_order_violations, check_repo, compare,
    defaulted_static_methods, extract_declarations, source_lines,
    split_namesake, unapplied_default_references,
)

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

    def test_rehome_turns_a_split_extension_into_a_superclass(self):
        suite = (
            "import XCTest\n\n"
            "final class SampleTests: XCTestCase {\n"
            '    private let account = "a"\n'
            '    private let ownerId = "owner"\n'
            "    func testKeepsOwner() {\n"
            "        _ = account\n"
            "        _ = ownerId\n"
            "    }\n"
            "}\n"
        )
        companion = (
            "import XCTest\n\n"
            "extension SampleTests {\n"
            "    func helper() -> String { account }\n"
            "}\n"
        )
        suite_out, companion_out = ratchet.rehome_suite_extension(suite, companion)
        self.assertIn("final class SampleTests: SampleFixtureCase {", suite_out)
        self.assertNotIn("let account", suite_out)
        self.assertIn('private let ownerId = "owner"', suite_out)
        self.assertIn("class SampleFixtureCase: XCTestCase {", companion_out)
        self.assertIn('let account = "a"', companion_out)
        self.assertNotIn("private let account", companion_out)
        self.assertNotIn("extension SampleTests", companion_out)
        self.assertNotIn("ownerId", companion_out)

    def test_pack_rehomes_a_suite_extension_instead_of_stranding_it(self):
        source = (
            "import XCTest\n\n"
            "final class SampleTests: XCTestCase {\n"
            '    let account = "a"\n'
            "    func testOne() { _ = account }\n"
            "}\n\n"
            "extension SampleTests {\n"
            "    func helper() -> String { account }\n"
            "}\n"
        )
        limit = ratchet.line_count(source) - 1
        bodies = ratchet.pack(source, limit)
        self.assertGreater(len(bodies), 1)
        self.assertEqual(ratchet.stranded_suite_extensions(bodies), [])
        self.assertNotIn("extension SampleTests", "\n".join(bodies))
        self.assertTrue(any("class SampleFixtureCase: XCTestCase" in body for body in bodies))
        self.assertTrue(any("class SampleTests: SampleFixtureCase" in body for body in bodies))

    def test_namesake_split_also_rehomes_fixture_and_preserves_raw_strings(self):
        source = (
            "import XCTest\n\n"
            "final class SampleTests: XCTestCase {\n"
            '    let account = #"brace { quoted " still"#\n'
            "    func testOne() { _ = account }\n"
            "}\n\n"
            "extension SampleTests {\n"
            "    func helper() -> String { account }\n"
            "}\n"
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "SampleTests.swift"
            path.write_text(source)
            paths = ratchet.apply_split(path, 8)
            self.assertEqual(paths[0], path)
            self.assertIn("class SampleTests: SampleFixtureCase", path.read_text())
            self.assertNotIn("let account", path.read_text())
            helper = Path(directory) / "SampleFixtureCase.swift"
            self.assertIn('let account = #"brace { quoted " still"#', helper.read_text())
            self.assertIn("class SampleFixtureCase: XCTestCase", helper.read_text())
            self.assertTrue(all(ratchet.line_count(p.read_text()) <= 8 for p in paths))

    def test_visualization_fixtures_are_an_independent_suite(self):
        suite = (ROOT / OWNED[2]).read_text()
        fixture = (ROOT / OWNED[3]).read_text()
        self.assertNotIn("extension BodyVisualizationSnapshotTests", fixture)
        self.assertIn("class BodyVisualizationSnapshotFixtureCase: XCTestCase", fixture)
        self.assertIn(
            "final class BodyVisualizationSnapshotTests: BodyVisualizationSnapshotFixtureCase",
            suite,
        )
        self.assertIn('let account = "fixture-account"', fixture)
        self.assertNotIn('let account = "fixture-account"', suite)



NAMESAKE = (
    "import Foundation\n\n"
    "enum Alpha {\n    let value = 1\n}\n\n"
    "enum Holder {\n    let value = 2\n}\n"
)
CALLS = """
func request(online: Bool, route: String, consentGranted: Bool) {}
func addBreadcrumb(message: String, category: String, level: String, data: [String: String]) {}
let good = request(online: false, route: "ext", consentGranted: true)
let omitted = request(route: "ext", consentGranted: true)
let bad = request(route: "ext", consentGranted: true, online: false)
let vendor = ErrorTrackingService.addBreadcrumb(level: "i", category: "c", message: "m", data: [:])
"""


class SplitSizeRatchetTest(unittest.TestCase):
    def test_cli_preserves_extraction_and_fixture_rehoming_after_a_merge(self):
        # Exercise both parents' repair modes through the same raw-string parser.
        original = (
            'import XCTest\n\nenum AttachmentKind {\n    let raw = #"brace { quoted " still"#\n}\n\n'
            'final class SampleTests: XCTestCase {\n    let account = "fixture"\n'
            '    func testOne() { _ = helper() }\n}\n\n'
            'extension SampleTests {\n    func helper() -> String { account }\n}\n'
        )
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "SampleTests.swift"
            sibling = Path(directory) / "AttachmentKind.swift"
            source.write_text(original)
            command = [sys.executable, str(ROOT / "scripts/ios/split_size_ratchet.py"), str(source)]
            extracted = subprocess.run(command + ["--extract", "AttachmentKind", "--sibling", str(sibling)],
                                       capture_output=True, text=True)
            self.assertEqual(extracted.returncode, 0, extracted.stderr)
            self.assertIn('let raw = #"brace { quoted " still"#', sibling.read_text())
            self.assertNotIn("AttachmentKind", source.read_text())
            split = subprocess.run(command + ["--limit", "8"], capture_output=True, text=True)
            self.assertEqual(split.returncode, 0, split.stderr)
            self.assertIn("class SampleTests: SampleFixtureCase", source.read_text())
            fixture = (Path(directory) / "SampleFixtureCase.swift").read_text()
            self.assertIn("class SampleFixtureCase: XCTestCase", fixture)
            self.assertIn('let account = "fixture"', fixture)
            self.assertNotIn("extension SampleTests", fixture)
            for path in Path(directory).glob("*.swift"):
                self.assertLessEqual(len(path.read_text().splitlines()), 8)

    def test_extract_keeps_complete_members_and_their_comments(self):
        source = (
            "import SwiftUI\n\nextension Home {\n"
            "    // A brace in a string must not end the member.\n"
            "    var photo: String {\n        \"}\"\n    }\n\n"
            "    func refresh() {\n        if true { print(\"{\") }\n    }\n}\n"
            "\n#Preview { Home() }\n"
        )
        kept, moved = extract_declarations(source, ["photo"], "Home")
        self.assertNotIn("var photo", kept)
        self.assertIn('func refresh()', kept)
        self.assertIn('#Preview { Home() }', kept)
        self.assertIn('// A brace', moved)
        self.assertIn('var photo: String {\n        "}"\n    }', moved)
        self.assertTrue(moved.startswith("import SwiftUI\n\nextension Home {"))
        self.assertEqual(extract_declarations(NAMESAKE, ["Alpha"])[1],
                         "import Foundation\n\nenum Alpha {\n    let value = 1\n}\n")

    def test_extract_refuses_missing_duplicate_or_private_declarations(self):
        for source, names, owner in [
            (NAMESAKE, ["Missing"], None),
            (NAMESAKE, ["Alpha", "Alpha"], None),
            ("extension Home {\n    private var value: Int { 1 }\n}\n", ["value"], "Home"),
            ("struct Home {\n    var value = 1\n    func next() {}\n}\n", ["value"], "Home"),
            ("struct Home {\n    var value = { 1 }()\n}\n", ["value"], "Home"),
        ]:
            with self.assertRaises(ValueError):
                extract_declarations(source, names, owner)

    def test_extract_cli_refuses_collision_and_oversize_before_writing(self):
        with tempfile.TemporaryDirectory() as tmp:
            source, sibling = Path(tmp) / "Home.swift", Path(tmp) / "Photo.swift"
            original = "import SwiftUI\n\nextension Home {\n    var photo: Int { 1 }\n}\n"
            source.write_text(original)
            command = [sys.executable, str(ROOT / "scripts/ios/split_size_ratchet.py"), str(source),
                       "--owner", "Home", "--extract", "photo", "--sibling", str(sibling)]
            for existing, extra in [("retained sibling", []), (None, ["--limit", "1"])]:
                if existing is not None:
                    sibling.write_text(existing)
                else:
                    sibling.unlink()
                result = subprocess.run(command + extra, capture_output=True, text=True)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(source.read_text(), original)
                self.assertEqual(sibling.read_text() if sibling.exists() else None, existing)
            self.assertEqual(subprocess.run(command, capture_output=True).returncode, 0)
            self.assertNotIn("var photo", source.read_text())
            self.assertIn("var photo: Int { 1 }", sibling.read_text())

    def test_namesake_split_does_not_overwrite_the_original(self):
        parts = split_namesake(NAMESAKE, "Holder.swift", 6)
        names = [name for name, _body in parts]
        self.assertEqual(names, ["Holder.swift", "Alpha.swift"])
        for _name, body in parts:
            self.assertLessEqual(source_lines(body), 6)
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "Holder.swift"
            source.write_text(NAMESAKE)
            (Path(tmp) / "Alpha.swift").write_text("existing\n")
            with self.assertRaises(ValueError) as raised:
                apply_split(source, 6)
            self.assertIn("overwrite", str(raised.exception))

    def test_grown_baselined_file_fails_and_new_oversized_file_fails(self):
        self.assertTrue(any("grew" in item for item in compare({"a.swift": 11}, {"a.swift": 10})))
        self.assertTrue(any("not baselined" in item for item in compare({"new.swift": 501}, {})))
        self.assertEqual(compare({"a.swift": 10}, {"a.swift": 10}), [])

    def test_defaulted_method_reference_is_rejected_until_it_is_called(self):
        declaration = (
            "enum PersonalBodyDay {\n"
            "    static func key(_ date: Date, calendar: Calendar = .current) -> String { \"\" }\n"
            "}\n"
        )
        methods = defaulted_static_methods(declaration)
        bad = "let dates = items.map(PersonalBodyDay.key)\n"
        good = "let dates = items.map { PersonalBodyDay.key($0) }\n"
        self.assertEqual(unapplied_default_references(bad, methods), [(1, "PersonalBodyDay.key")])
        self.assertEqual(unapplied_default_references(good, methods), [])

    def test_argument_order_rejects_online_after_route(self):
        violations = argument_order_violations(CALLS)
        self.assertEqual(len(violations), 1)
        _line, name, order = violations[0]
        self.assertEqual(name, "request")
        self.assertEqual(order, ["route", "consentGranted", "online"])

    def test_branch_sources_meet_the_company_limit(self):
        baseline = json.loads((ROOT / ".company-guards" / "size-baseline.json").read_text())
        sheet = "apps/ios/LogYourBody/Views/ProgressPhotoAttachSheet.swift"
        self.assertLessEqual(source_lines((ROOT / sheet).read_text()), baseline[sheet])
        under_limit = [
            "apps/ios/LogYourBody/Components/PersonalBodyEstimate.swift",
            "apps/ios/LogYourBody/Components/PersonalBodyViewKind.swift",
            "apps/ios/LogYourBody/Views/ProgressPhotoAttachSheet+PersonalBody.swift",
            "packages/shared-lib/src/personal-body-estimate.ts",
            "packages/shared-lib/src/personal-body-estimate-model.ts",
            "scripts/resolve-repository-docs.test.mjs",
            "scripts/resolve-repository-docs-manifest.test.mjs",
            "scripts/ios/split_size_ratchet.py",
            "scripts/ios/test_split_size_ratchet.py",
        ]
        for rel in under_limit:
            count = source_lines((ROOT / rel).read_text())
            self.assertLessEqual(count, 500, rel)
        order = argument_order_violations(
            (ROOT / "apps/ios/LogYourBodyTests/PersonalBodyEstimateTests.swift").read_text()
        )
        self.assertEqual(order, [])
        self.assertEqual(check_repo(ROOT), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
