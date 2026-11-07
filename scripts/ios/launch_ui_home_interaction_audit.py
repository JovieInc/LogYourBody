"""Home-column and synthetic-typing checks for the launch UI regression audit."""

from __future__ import annotations

from pathlib import Path
import re

from launch_ui_timeline_audit import text_for


def function_body(text: str, name: str, next_name: str) -> str:
    if f"func {name}" not in text or f"func {next_name}" not in text:
        return ""
    chunk = text.split(f"func {name}", 1)[1].split(f"func {next_name}", 1)[0]
    return chunk.split("{", 1)[1] if "{" in chunk else ""


def contribute(root: Path, app_dir: Path, violations: list, violation, _line_number) -> None:
    check(root, app_dir, violations, function_body, violation)
    check_person_mask_executor(root, app_dir, violations, violation)
    check_logout_alert(root, violations, violation)
    check_ui_test_offline_fixture(root, violations, violation)


def check_person_mask_executor(root: Path, app_dir: Path, violations: list, violation) -> None:
    """Blocking Vision segmentation must leave the Swift cooperative pool available."""
    path = app_dir / "Services/BackgroundRemovalService.swift"
    text = text_for(path)
    body = text.split("func personMask(", 1)[-1].split("func personMaskGrid(", 1)[0]
    queue = re.search(
        r"segmentationQueue\s*:\s*DispatchQueue\s*=\s*DispatchQueue\(([^)]*)\)", text
    )
    if ("Task.detached" in body or "withCheckedThrowingContinuation" not in body
            or "segmentationQueue.async {" not in body or queue is None
            or ".concurrent" in queue.group(1)):
        violations.append(violation(
            check="photo.segmentation_dispatch_executor",
            file=str(path.relative_to(root)), line=1,
            detail="Run blocking person segmentation asynchronously on a serial Dispatch queue, outside Swift's cooperative pool.",
        ))


def check(root: Path, app_dir: Path, violations: list, function_body, violation) -> None:
    """The provenance chip stays above the weekly prompt, and typed characters refocus."""
    surface = app_dir / "Views/HomeV2/HomeV2Surface.swift"
    text = text_for(surface)
    body = text.split("var body: some View {", 1)[-1].split("private var systemBanner", 1)[0]
    numbers = text.split("private var photoNumberBlock: some View {", 1)[-1].split(
        "private var ffmiSummary", 1
    )[0]
    prompt = "WeeklyPhotoCheckInPrompt("
    chip = "HomeV2ProvenanceChip("
    rendered = body.replace("photoNumberBlock", numbers, 1)
    prompt_at = rendered.find(prompt)
    chip_at = rendered.find(chip)
    if prompt_at < 0 or chip_at < 0 or prompt_at < chip_at:
        violations.append(violation(
            check="home.provenance_chip_precedes_weekly_prompt",
            file=str(surface.relative_to(root)),
            line=1,
            detail="Place the weekly photo prompt after the provenance chip so the chip stays above the dock.",
        ))

    ui_tests = root / "apps/ios/LogYourBodyUITests/LogYourBodyUITests.swift"
    if not ui_tests.is_file():
        return
    loop = function_body(
        text_for(ui_tests),
        "submitSyntheticChatQuestion",
        "enteredSyntheticQuestion",
    )
    character = loop.split("for character in addition", 1)[-1] if "for character in addition" in loop else ""
    type_at = character.find("typeText(")
    focus_at = character.find("keyboard.exists")
    if type_at < 0 or focus_at < 0 or focus_at > type_at:
        violations.append(violation(
            check="chat.synthetic_typing_refocuses",
            file=str(ui_tests.relative_to(root)),
            line=1,
            detail="Refocus the composer when the keyboard drops before each synthetic character.",
        ))


def check_logout_alert(root: Path, violations: list, violation) -> None:
    """Duplicate accessibility wrappers must resolve to one physical alert action."""
    path = root / "apps/ios/LogYourBodyUITests/LogYourBodyUITests.swift"
    if not path.is_file():
        return
    text = text_for(path)
    helper = function_body(text, "hittableLogoutAction", "testProfileEditorProvidesAnEscapeRoute")
    journey = function_body(text, "testProfileLogoutSignsOutFromPushedDetail", "hittableLogoutAction")
    required = (
        "alert.buttons.matching(identifier: identifier)",
        "$0.label == label && $0.isEnabled && $0.isHittable",
        "reduce(into: [XCUIElement]())",
        "!unique.contains(where: { $0.frame == action.frame })",
        "unique.append(action)",
        "interactiveActions().count == 1",
        "actions.count == 1 ? actions.first : nil",
    )
    outcomes = (
        'identifier: "settings_logout_cancel", label: "Cancel"',
        "cancelLogout.tap()",
        "XCTAssertTrue(logoutConfirmation.waitForNonExistence(timeout: 5))",
        "XCTAssertTrue(logoutButton.exists)",
        'XCTAssertFalse(app.buttons["continueWithAppleButton"].exists)',
        'identifier: "settings_logout_confirm", label: "Log Out"',
        "confirmLogout.tap()",
        'XCTAssertTrue(app.buttons["continueWithAppleButton"].waitForExistence(timeout: 8))',
    )
    if (any(token not in helper for token in required)
            or "descendants(matching: .button)" in helper
            or any(token not in journey for token in outcomes)):
        violations.append(violation(
            check="logout.alert_action_identity", file=str(path.relative_to(root)), line=1,
            detail="Collapse identical alert action frames, reject distinct matches, and verify Cancel and Log Out outcomes.",
        ))


def check_ui_test_offline_fixture(root: Path, violations: list, violation) -> None:
    """A satisfied network path must not clear the UI-test offline fixture."""
    app = root / "apps/ios/LogYourBody/LogYourBodyApp.swift"
    sync = root / "apps/ios/LogYourBody/Services/RealtimeSyncManager.swift"
    monitor = root / "apps/ios/LogYourBody/Services/RealtimeSyncManager+Part01.swift"
    if not app.is_file() or not sync.is_file() or not monitor.is_file():
        return
    fixture = text_for(app).split("func applyPaidMVPUITestFixtureIfNeeded", 1)[-1].split(
        "func writeHomeV2FixturePhoto", 1
    )[0]
    policy = text_for(sync).split("func argumentsForceUITestOffline", 1)[-1].split(
        "func applyNetworkPathStatus", 1
    )[0]
    applicator = text_for(sync).split("func applyNetworkPathStatus", 1)[-1]
    handler = text_for(monitor).split("func setupNetworkMonitoring", 1)[-1].split(
        "func setupAuthListener", 1
    )[0]
    required = (
        "-lybUITestPaidMVPFixture",
        "-lybUITestWeightLoggerMVPFixture",
        "-lybUITestPaywallFixture",
        "-lybUITestPaywallPlansFixture",
        "-lybUITestFullDashboardFixture",
        "-lybUITestPhotoTimelineHUDFixture",
        "-lybUITestBodyScoreOnboardingFixture",
        "-lybUITestBodyScoreFirstPhotoFixture",
    )
    held = applicator.find("argumentsForceUITestOffline")
    assigned = applicator.find("isOnline = status ==")
    if (any(token not in fixture or token not in policy for token in required)
            or "argumentsForceUITestOffline(arguments)" not in fixture
            or "isOnline = false" not in fixture
            or held < 0 or assigned < 0 or "return" not in applicator[held:assigned]
            or "applyNetworkPathStatus(path.status)" not in handler
            or "isOnline = path.status" in handler):
        violations.append(violation(
            check="sync.ui_test_offline_survives_path",
            file=str(monitor.relative_to(root)),
            line=1,
            detail="A UI-test offline fixture must survive a satisfied network path.",
        ))
