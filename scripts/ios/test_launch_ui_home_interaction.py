"""Mutation cases shared by the existing required launch UI audit suite."""

from pathlib import Path
import shutil

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

    def test_ui_test_offline_fixture_survives_a_satisfied_path(self):
        sync = self.app / "Services/RealtimeSyncManager.swift"
        monitor = self.app / "Services/RealtimeSyncManager+Part01.swift"
        original_sync = sync.read_text()
        original_monitor = monitor.read_text()
        self.assertEqual(self.run_audit()[0], 0)
        cases = [
            (sync, original_sync, '"-lybUITestPhotoTimelineHUDFixture",\n', ""),
            (sync, original_sync, "disconnectRealtime()\n            return", "disconnectRealtime()"),
            (monitor, original_monitor, "self?.applyNetworkPathStatus(path.status)",
             "self?.isOnline = path.status == .satisfied"),
        ]
        for path, original, before, after in cases:
            with self.subTest(before=before):
                self.assertIn(before, original)
                path.write_text(original.replace(before, after, 1))
                self.assert_rejected("sync.ui_test_offline_survives_path")
                path.write_text(original)
