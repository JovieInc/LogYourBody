"""Home-column and synthetic-typing checks for the launch UI regression audit."""

from __future__ import annotations

from pathlib import Path


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
