"""Home-column and synthetic-typing checks for the launch UI regression audit."""

from __future__ import annotations

from pathlib import Path
import re


def function_body(text: str, name: str, next_name: str) -> str:
    if f"func {name}" not in text or f"func {next_name}" not in text:
        return ""
    chunk = text.split(f"func {name}", 1)[1].split(f"func {next_name}", 1)[0]
    return chunk.split("{", 1)[1] if "{" in chunk else ""


def contribute(root: Path, app_dir: Path, violations: list, violation, _line_number) -> None:
    check(root, app_dir, violations, function_body, violation)
    check_person_mask_executor(root, app_dir, violations, violation)


def check_person_mask_executor(root: Path, app_dir: Path, violations: list, violation) -> None:
    """Blocking Vision segmentation must leave the Swift cooperative pool available."""
    path = app_dir / "Services/BackgroundRemovalService.swift"
    text = path.read_text()
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
    text = surface.read_text(errors="replace")
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
        ui_tests.read_text(errors="replace"),
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
