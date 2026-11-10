"""Mutation cases shared by the existing required launch UI audit suite."""

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path
import shutil
from launch_ui_offline_pin_audit import check_ui_test_offline_pin

ROOT = Path(__file__).resolve().parents[2]


class HomeInteractionAuditTests:
    def test_weekly_prompt_cannot_precede_the_provenance_chip(self):
        path = self.app / "Views/HomeV2/HomeV2Surface.swift"
        source = path.read_text()
        prompt = (
            "            if let weeklyPhotoPrompt {\n"
            "                WeeklyPhotoCheckInPrompt(prompt: weeklyPhotoPrompt, onAdd: onAddWeeklyPhoto)\n"
            "            }\n"
        )
        self.assertEqual(source.count(prompt), 1)
        self.assertEqual(self.run_audit()[0], 0)
        moved = source.replace(prompt, "", 1).replace(
            "                    photoNumberBlock\n",
            prompt + "                    photoNumberBlock\n",
            1,
        )
        path.write_text(moved)
        self.assert_rejected("home.provenance_chip_precedes_weekly_prompt")

    def test_synthetic_character_entry_refocuses_a_dropped_keyboard(self):
        destination = self.root / "apps/ios/LogYourBodyUITests/LogYourBodyUITests.swift"
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / destination.relative_to(self.root), destination)
        self.assertEqual(self.run_audit()[0], 0)
        source = destination.read_text()
        self.assertIn("if !keyboard.exists {", source)
        destination.write_text(source.replace("if !keyboard.exists {\n", "if false {\n", 1))
        self.assert_rejected("chat.synthetic_typing_refocuses")

    def test_person_segmentation_cannot_block_the_swift_cooperative_pool(self):
        path = self.app / "Services/BackgroundRemovalService.swift"
        original = path.read_text()
        self.assertEqual(self.run_audit()[0], 0)
        for before, after in [
            ("segmentationQueue.async {", "Task.detached(priority: .userInitiated) {"),
            ("segmentationQueue.async {", "segmentationQueue.sync {"),
            ("qos: .userInitiated)", "qos: .userInitiated, attributes: .concurrent)"),
        ]:
            with self.subTest(before=before, after=after):
                self.assertIn(before, original)
                path.write_text(original.replace(before, after, 1))
                self.assert_rejected("photo.segmentation_dispatch_executor")
        path.write_text(original)

    def test_logout_alert_requires_one_distinct_action_and_both_outcomes(self):
        destination = self.root / "apps/ios/LogYourBodyUITests/LogYourBodyUITests.swift"
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / destination.relative_to(self.root), destination)
        source = destination.read_text()
        self.assertEqual(self.run_audit()[0], 0)
        prefix, journey = source.split("    func testProfileLogoutSignsOutFromPushedDetail", 1)
        for before, after in [
            ("alert.buttons.matching(identifier: identifier)", "app.buttons.matching(identifier: identifier)"),
            ("$0.label == label && $0.isEnabled && $0.isHittable", "$0.isHittable"),
            ("$0.frame == action.frame", "false"),
            ("actions.count == 1 ? actions.first : nil", "actions.first"),
            ("logoutConfirmation.waitForNonExistence(timeout: 5)", "true"),
            ('app.buttons["continueWithAppleButton"].waitForExistence(timeout: 8)', "true"),
        ]:
            with self.subTest(before=before):
                self.assertIn(before, journey)
                destination.write_text(prefix + "    func testProfileLogoutSignsOutFromPushedDetail"
                                       + journey.replace(before, after, 1))
                self.assert_rejected("logout.alert_action_identity")
        destination.write_text(source)

    def test_profile_logout_confirmation_stays_on_the_pushed_row(self):
        self.assertEqual(self.run_audit()[0], 0)
        cases = [
            (
                "SettingsComponents.swift",
                "settingsButtonLabel\n"
                "                .frame(maxWidth: .infinity, minHeight: SettingsLayout.rowMinHeight, alignment: .leading)\n"
                "                .contentShape(Rectangle())",
                "settingsButtonLabel",
            ),
            (
                "SettingsComponents.swift",
                ".frame(maxWidth: .infinity, minHeight: SettingsLayout.rowMinHeight, alignment: .leading)",
                ".frame(minHeight: SettingsLayout.rowMinHeight, alignment: .leading)",
            ),
            (
                "Views/PreferencesView+Header.swift",
                "@State private var showingLogoutConfirmation = false",
                "@State private var unusedLogoutConfirmation = false",
            ),
            (
                "Views/PreferencesView+AccountSection.swift",
                "showingLogoutConfirmation.wrappedValue = true",
                "showingLogoutConfirmation.wrappedValue = false",
            ),
        ]
        for relative, before, after in cases:
            with self.subTest(before=before):
                path = self.app / relative
                source = path.read_text()
                self.assertIn(before, source)
                path.write_text(source.replace(before, after, 1))
                self.assert_rejected("logout.profile_confirmation_hit_target")
                path.write_text(source)

    def test_ui_test_offline_fixture_survives_a_satisfied_path(self):
        sync = self.app / "Services/RealtimeSyncManager.swift"
        monitor = self.app / "Services/RealtimeSyncManager+Part01.swift"
        app = self.app / "LogYourBodyApp.swift"
        original_sync = sync.read_text()
        original_monitor = monitor.read_text()
        original_app = app.read_text()
        self.assertEqual(self.run_audit()[0], 0)
        cases = [
            (sync, original_sync, '"-lybUITestPhotoTimelineHUDFixture",\n', ""),
            (sync, original_sync, "return !fixtureForcesOffline", "return pathSatisfied"),
            (monitor, original_monitor, "self?.handleNetworkPathUpdate(isOnline: path.status == .satisfied)",
             "self?.isOnline = path.status == .satisfied"),
            (monitor, original_monitor, "self?.handleNetworkPathUpdate(isOnline: path.status == .satisfied)",
             "self?.handleNetworkPathUpdate(isOnline: path.status == .satisfied)\n"
             "                self?.handleNetworkPathUpdate(isOnline: path.status == .satisfied)"),
            (monitor, original_monitor, "self?.handleNetworkPathUpdate(isOnline: path.status == .satisfied)",
             "self?.handleNetworkPathUpdate(isOnline: path.status == .satisfied)\n"
             "                self?.applyNetworkPathStatus(path.status)"),
            (app, original_app, "realtimeSyncManager.applyOfflineUITestFixture()\n", ""),
            (sync, original_sync, "networkMonitor.cancel()\n        isOnline = false",
             "networkMonitor.cancel()"),
        ]
        for path, original, before, after in cases:
            with self.subTest(before=before):
                self.assertIn(before, original)
                path.write_text(original.replace(before, after, 1))
                self.assert_rejected("sync.ui_test_offline_survives_path")
                path.write_text(original)


    def test_satisfied_path_cannot_clear_a_ui_test_offline_pin(self):
        sync = self.app / "Services/RealtimeSyncManager+Part01.swift"
        manager = self.app / "Services/RealtimeSyncManager.swift"
        app = self.app / "LogYourBodyApp.swift"
        originals = {path: path.read_text() for path in (sync, manager, app)}
        def checks():
            texts = {path: path.read_text() for path in originals}
            found = []
            check_ui_test_offline_pin(self.root, [], found, texts)
            return [item.check for item in found]
        self.assertEqual(checks(), [])
        cases = (
            (sync, "self?.handleNetworkPathUpdate(isOnline: path.status == .satisfied)", "self.isOnline = path.status == .satisfied"),
            (manager, "guard !usesOfflineUITestFixture else { return }", "guard usesOfflineUITestFixture else { return }"),
            (app, "realtimeSyncManager.applyOfflineUITestFixture()", "realtimeSyncManager.isOnline = false"),
        )
        for path, before, after in cases:
            with self.subTest(path=path.name):
                path.write_text(originals[path].replace(before, after, 1))
                self.assertEqual(checks(), ["sync.ui_test_offline_pin"])
                path.write_text(originals[path])

    def test_dated_stats_fixture_survives_path_and_account_change(self):
        self.assertEqual(self.run_audit()[0], 0)
        cases = [
            ("Services/RealtimeSyncManager+Part01.swift", "self?.handleNetworkPathUpdate(isOnline: path.status == .satisfied)", "self.isOnline = path.status == .satisfied", "dated_stats.offline_survives_path"),
            ("Services/RealtimeSyncManager.swift", "self.isOnline = Self.online(isOnline)", "self.isOnline = isOnline", "dated_stats.offline_survives_path"),
            ("Services/RealtimeSyncManager.swift", "guard !usesOfflineUITestFixture else { return }", "", "dated_stats.offline_survives_path"),
            ("Services/RealtimeSyncManager.swift", "return !fixtureForcesOffline", "return pathSatisfied", "dated_stats.offline_survives_path"),
            ("Services/RealtimeSyncManager.swift", '"-lybUITestPhotoTimelineHUDFixture"', '"-not-an-offline-fixture"', "dated_stats.offline_survives_path"),
            ("Views/DashboardViewLiquid.swift", "selectedPhotoTimelineRootPage = Self.pageAfterAccountChange()", "selectedPhotoTimelineRootPage = .timeline", "dated_stats.analytics_survives_account"),
            ("Services/DatedTimelineUI.swift", "return .analytics", "return .timeline", "dated_stats.analytics_survives_account"),
        ]
        for relative, before, after, check in cases:
            with self.subTest(before=before):
                path = self.app / relative
                source = path.read_text()
                self.assertIn(before, source)
                path.write_text(source.replace(before, after, 1))
                self.assert_rejected(check)
                path.write_text(source)


def launch_ui_audit():
    """Return the audit module already loaded by the behavior suite."""
    loaded = sys.modules.get("launch_ui_audit")
    if loaded is not None:
        return loaded
    root = Path(__file__).resolve().parents[2]
    spec = importlib.util.spec_from_file_location(
        "launch_ui_audit", root / "scripts/ios/launch-ui-regression-audit.py",
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class CheckSiblingDiscoveryTests(unittest.TestCase):
    def test_every_size_ratchet_sibling_loads_or_the_audit_fails_closed(self):
        audit = launch_ui_audit()
        loaded = [
            audit._load_sibling(module_name, filename, export)
            for module_name, filename, export in audit._AUDIT_SIBLINGS
        ]
        self.assertEqual(
            [item[0] for item in audit._AUDIT_SIBLINGS],
            [
                "launch_ui_timeline_day",
                "launch_ui_opacity_audit",
                "launch_ui_timeline_gesture_audit",
                "launch_ui_offline_pin_audit",
                "launch_ui_dated_stats_audit",
                "launch_ui_regression_report",
            ],
        )
        for export in loaded:
            self.assertTrue(callable(export))
        with self.assertRaises(RuntimeError) as missing_file:
            audit._load_sibling("missing_sibling", "missing_launch_ui_sibling.py", "missing")
        self.assertIn("Cannot load launch UI audit sibling", str(missing_file.exception))
        with self.assertRaises(RuntimeError) as missing_export:
            audit._load_sibling(
                "launch_ui_timeline_day", "launch_ui_timeline_day.py", "not_an_export",
            )
        self.assertIn("Cannot load launch UI audit sibling", str(missing_export.exception))

    def test_every_check_sibling_contributes_and_a_missing_hook_fails_closed(self):
        # The coverage tracer reads these modules after the suite returns.
        audit = launch_ui_audit()
        directory = Path(tempfile.mkdtemp(prefix="lyb-audit-siblings-"))
        (directory / "launch_ui_beta.py").write_text(
            "def contribute(bucket, *args):\n    bucket.append('beta')\n"
        )
        (directory / "launch_ui_alpha.py").write_text(
            "def contribute(bucket, *args):\n    bucket.append('alpha')\n"
        )
        (directory / "notes.py").write_text("def contribute(bucket, *args):\n    bucket.append('nope')\n")
        seen = []
        for module in audit.load_check_siblings(directory):
            module.contribute(seen)
        self.assertEqual(seen, ["alpha", "beta"])
        (directory / "launch_ui_broken.py").write_text("def check():\n    return None\n")
        with self.assertRaises(RuntimeError) as broken:
            audit.load_check_siblings(directory)
        self.assertIn("Cannot load launch UI audit sibling", str(broken.exception))
        empty = directory / "empty"
        empty.mkdir()
        with self.assertRaises(RuntimeError) as missing:
            audit.load_check_siblings(empty)
        self.assertIn("Cannot load launch UI audit sibling", str(missing.exception))
        with self.assertRaises(RuntimeError) as absent:
            audit._load_sibling("absent.py", "absent.py", empty)
        self.assertIn("Cannot load launch UI audit sibling", str(absent.exception))

    def test_required_named_sibling_cannot_hide_behind_audit_violation(self):
        audit = launch_ui_audit()
        directory = Path(tempfile.mkdtemp(prefix="lyb-audit-required-"))
        (directory / "launch_ui_alpha.py").write_text(
            "def contribute(bucket, *args):\n    bucket.append('alpha')\n"
        )
        (directory / "launch_ui_gesture.py").write_text(
            "class AuditViolation:\n    pass\n"
            "def check_timeline_gestures():\n    return None\n"
        )
        required = (("launch_ui_gesture", "launch_ui_gesture.py", "check_timeline_gestures"),)
        with self.assertRaises(RuntimeError) as hidden:
            audit.load_check_siblings(directory, required=required)
        self.assertIn("launch_ui_gesture.py", str(hidden.exception))
        (directory / "launch_ui_gesture.py").write_text(
            "class AuditViolation:\n    pass\n"
            "def check_timeline_gestures():\n    return None\n"
            "def contribute(bucket, *args):\n    bucket.append('gesture')\n"
        )
        seen = []
        for module in audit.load_check_siblings(directory, required=required):
            module.contribute(seen)
        self.assertEqual(seen, ["alpha", "gesture"])

    def test_shipped_check_siblings_include_home_and_timeline(self):
        names = [module.__name__ for module in launch_ui_audit()._CHECK_SIBLINGS]
        self.assertIn("launch_ui_home_interaction_audit", names)
        self.assertIn("launch_ui_timeline_day", names)
        self.assertIn("launch_ui_opacity_audit", names)
        self.assertIn("launch_ui_timeline_gesture_audit", names)
        self.assertNotIn("launch_ui_timeline_audit", names)
        self.assertNotIn("launch_ui_timeline_calendar_audit", names)
