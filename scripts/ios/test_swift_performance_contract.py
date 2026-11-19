"""Behavior tests for the per-surface Swift performance contract guard."""
import importlib.util
import json
import sys
import unittest
from pathlib import Path


spec = importlib.util.spec_from_file_location("swift_performance_guard", Path(__file__).with_name("swift-performance-guard.py"))
guard = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = guard
spec.loader.exec_module(guard)

ROOT = Path(__file__).resolve().parents[2]


class SwiftPerformanceContractTests(unittest.TestCase):
    def test_new_violation(self):
        source = "\n".join([
            "struct Home: View {",
            "    var body: some View {",
            "        // DispatchQueue.main.sync { }",
            "        DispatchQueue.main.sync { }",
            "        Thread.sleep(forTimeInterval: 1)",
            "        _ = DispatchSemaphore(value: 0)",
            "        context.performAndWait { }",
            "        _ = UIImage(data: data)",
            "    }",
            "}",
            "let image = UIImage(data: data)",
        ])
        findings = guard.scan_source("apps/ios/LogYourBody/Views/Home.swift", source)
        rules = {finding.rule for finding in findings}
        self.assertIn("interaction.main_sync", rules)
        self.assertIn("interaction.thread_sleep", rules)
        self.assertIn("interaction.dispatch_semaphore", rules)
        self.assertIn("interaction.perform_and_wait", rules)
        self.assertIn("interaction.uiimage_data_in_view_body", rules)
        self.assertEqual(sum(1 for finding in findings if finding.rule == "interaction.main_sync"), 1)
        service = guard.scan_source("apps/ios/LogYourBody/Services/Sync.swift", "context.performAndWait {}\nlet image = UIImage(data: data)\n")
        self.assertEqual([finding.rule for finding in service], ["interaction.perform_and_wait"])
        self.assertTrue(guard.ratchet_errors(guard.counts_of(findings), {}))

    def test_stale_high_baseline(self):
        live = {"interaction.thread_sleep|apps/ios/LogYourBody/Views/Home.swift": 1}
        baseline = {"interaction.thread_sleep|apps/ios/LogYourBody/Views/Home.swift": 2}
        errors = guard.ratchet_errors(live, baseline)
        self.assertEqual(len(errors), 1)
        self.assertIn("stale-high baseline", errors[0])
        self.assertEqual(guard.ratchet_errors(live, dict(live)), [])
        self.assertTrue(guard.fall_only_errors({"interaction.thread_sleep|a.swift": 2}, {"interaction.thread_sleep|a.swift": 1}))
        self.assertEqual(guard.fall_only_errors({"interaction.thread_sleep|a.swift": 1}, {"interaction.thread_sleep|a.swift": 2}), [])

    def test_unknown_signpost(self):
        text = '\n'.join([
            '// PerfSignpost.measure("custom_span")',
            'PerfSignpost.measure("not_registered") { work() }',
            'PerfSignpost.event("launch_first_dashboard_frame", "")',
            'PerfSignpost.begin(dynamicName)',
        ])
        errors = guard.signpost_errors(text, {"launch_first_dashboard_frame"}, "Apps/Home.swift")
        self.assertTrue(any("unknown signpost not_registered" in error for error in errors))
        self.assertTrue(any("string literal" in error for error in errors))
        self.assertFalse(any("custom_span" in error or "launch_first_dashboard_frame" in error for error in errors))

    def test_drifted_toolchain_receipt(self):
        project = (ROOT / guard.PROJECT_REL).read_text()
        live = guard.build_toolchain_receipt(project)
        self.assertEqual(live["SWIFT_VERSION"], "5.0")
        self.assertEqual(live["swiftLanguageMode"], "5.0")
        self.assertIsNone(live["defaultActorIsolation"])
        self.assertFalse(live["concurrentAttributeEnabled"])
        drifted = json.loads(json.dumps(live))
        drifted["SWIFT_VERSION"] = "6.0"
        errors = guard.toolchain_drift_errors(live, drifted)
        self.assertTrue(errors)
        self.assertIn("drifted", errors[0])
        self.assertEqual(guard.toolchain_drift_errors(live, json.loads(json.dumps(live))), [])
        inherited = guard.parse_project(
            "\n".join([
                'AAAAAAAAAAAAAAAAAAAAAAAA /* Build configuration list for PBXProject "LogYourBody" */ = {',
                "\t\t\tisa = XCConfigurationList;",
                "\t\t\tbuildConfigurations = (",
                "\t\t\t\tBBBBBBBBBBBBBBBBBBBBBBBB /* Debug */,",
                "\t\t\t\tCCCCCCCCCCCCCCCCCCCCCCCC /* Release */,",
                "\t\t\t);",
                "\t\t};",
                "BBBBBBBBBBBBBBBBBBBBBBBB /* Debug */ = {",
                "\t\t\tisa = XCBuildConfiguration;",
                "\t\t\tbuildSettings = {",
                "\t\t\t\tSWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;",
                "\t\t\t};",
                "\t\t\tname = Debug;",
                "\t\t};",
                "CCCCCCCCCCCCCCCCCCCCCCCC /* Release */ = {",
                "\t\t\tisa = XCBuildConfiguration;",
                "\t\t\tbuildSettings = {",
                "\t\t\t\tSWIFT_VERSION = 5.0;",
                "\t\t\t};",
                "\t\t\tname = Release;",
                "\t\t};",
                'DDDDDDDDDDDDDDDDDDDDDDDD /* Build configuration list for PBXNativeTarget "LogYourBody" */ = {',
                "\t\t\tisa = XCConfigurationList;",
                "\t\t\tbuildConfigurations = (",
                "\t\t\t\tEEEEEEEEEEEEEEEEEEEEEEEE /* Debug */,",
                "\t\t\t\tFFFFFFFFFFFFFFFFFFFFFFFF /* Release */,",
                "\t\t\t);",
                "\t\t};",
                "EEEEEEEEEEEEEEEEEEEEEEEE /* Debug */ = {",
                "\t\t\tisa = XCBuildConfiguration;",
                "\t\t\tbuildSettings = {",
                "\t\t\t\tSWIFT_VERSION = 5.0;",
                "\t\t\t};",
                "\t\t\tname = Debug;",
                "\t\t};",
                "FFFFFFFFFFFFFFFFFFFFFFFF /* Release */ = {",
                "\t\t\tisa = XCBuildConfiguration;",
                "\t\t\tbuildSettings = {",
                "\t\t\t\tSWIFT_VERSION = 5.0;",
                "\t\t\t};",
                "\t\t\tname = Release;",
                "\t\t};",
            ])
        )
        debug = next(row for row in inherited if row["config"] == "Debug")
        self.assertEqual(debug["isolation"], "MainActor")
        self.assertTrue(guard.row_enables_concurrent(debug))
        self.assertFalse(guard.row_enables_concurrent({"isolation": None, "upcoming": [], "swift": "5.0"}))
        self.assertFalse(guard.uses_concurrent("// @concurrent func hidden() {}\n"))
        self.assertTrue(guard.uses_concurrent("@concurrent func work() {}\n"))

    def test_pass_receipt_missing_hardware_fields(self):
        status, errors = guard.validate_device_receipt({"verdict": "physical-pass", "device": "iPhone"})
        self.assertEqual(status, "rejected")
        self.assertTrue(errors)
        for field in ("os", "buildSha", "thermalState", "refreshRateHz", "fixtureId"):
            self.assertIn(field, errors[0])
        missing_status, missing_errors = guard.validate_device_receipt(None)
        self.assertEqual(missing_status, "unverified")
        self.assertEqual(missing_errors, [])
        complete = {
            "verdict": "physical-pass",
            "device": "iPhone16,1",
            "os": "iOS 26.0",
            "buildSha": "abc123",
            "thermalState": "nominal",
            "refreshRateHz": 120,
            "fixtureId": "photo-timeline",
        }
        verified, verified_errors = guard.validate_device_receipt(complete)
        self.assertEqual(verified, "verified")
        self.assertEqual(verified_errors, [])

    def test_checked_in_contract_holds(self):
        report = guard.evaluate(ROOT)
        self.assertEqual(report["errors"], [], "\n".join(report["errors"]))
        self.assertTrue(report["ok"])
        self.assertEqual(report["deviceReceipt"], "unverified")
        self.assertEqual(report["toolchain"]["SWIFT_VERSION"], "5.0")
        self.assertIsNone(report["toolchain"]["defaultActorIsolation"])
        self.assertFalse(report["toolchain"]["concurrentAttributeEnabled"])


if __name__ == "__main__":
    result = unittest.TextTestRunner().run(unittest.defaultTestLoader.loadTestsFromTestCase(SwiftPerformanceContractTests))
    print(f"Swift performance contract tests executed: {result.testsRun}")
    if not result.wasSuccessful() or result.testsRun == 0:
        sys.exit(1)
