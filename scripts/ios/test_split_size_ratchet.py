#!/usr/bin/env python3
"""The size-500 split ratchet keeps namesakes, baselines, and Swift argument order."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from split_size_ratchet import (  # noqa: E402
    apply_split,
    argument_order_violations,
    check_repo,
    compare,
    defaulted_static_methods,
    source_lines,
    split_namesake,
    unapplied_default_references,
)

ROOT = Path(__file__).resolve().parents[2]
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
        self.assertEqual(source_lines((ROOT / sheet).read_text()), baseline[sheet])
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
    unittest.main()
