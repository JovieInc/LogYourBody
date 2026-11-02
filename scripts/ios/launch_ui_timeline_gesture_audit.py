"""Timeline gesture checks for the launch UI regression audit.

Extracted so the parent audit stays within the company 500-line ratchet.
The audit loads this sibling by path.
"""

from __future__ import annotations

import re
from pathlib import Path


def check_timeline_gestures(root: Path, hud_path: Path, hud: str, violations: list, violation_cls) -> None:
    """Keep header and edge swipes off the menu button."""
    # Header navigation drags must not own either button's touch region.
    header_call = hud.split("photoTimelineRootNavigation\n", 1)[-1].split("photoTimelineHomeContent\n", 1)[0]
    header = hud.split("private var photoTimelineRootNavigation: some View {", 1)[-1].split(
        "private var photoTimelineSwipe:", 1
    )[0]
    title = header.split("VStack(spacing: 2) {", 1)[-1].split("if isHomeV2CheckIn {", 1)[0]
    gesture = re.compile(r"\.(?:gesture|simultaneousGesture|highPriorityGesture)\s*\(")
    if (gesture.search(header_call) or gesture.search(header.replace(title, ""))
            or ".gesture(photoTimelineSwipe)" not in title
            or ".contentShape(Rectangle())" not in title
            or "minHeight: JovieTokens.minimumHitTarget" not in title):
        violations.append(violation_cls(
            check="timeline.header_swipe_excludes_buttons", file=str(hud_path.relative_to(root)), line=1,
            detail="Attach the header swipe only to the full-height title hit region, outside the menu and detail buttons.",
        ))

    # The edge swipe must stay on the content below the header. Padding before
    # the gesture, or a parent overlay, lets that drag share the menu button.
    root_body = hud.split("var photoTimelineRoot: some View {", 1)[-1].split(
        "private var photoTimelineToolbarTitle", 1
    )[0]
    content_chain = root_body.split("photoTimelineHomeContent\n", 1)[-1].split(
        "if !isHomeV2CheckIn", 1
    )[0]
    parent_chain = root_body.split("if !isHomeV2CheckIn", 1)[-1]
    edge = ".highPriorityGesture(photoTimelineSwipe)"
    overlay = content_chain.split(".overlay(alignment: .leading)", 1)[-1].split("\n        }", 1)[0]
    padding_before_gesture = (
        ".padding(" in overlay and overlay.find(".padding(") < overlay.find(edge)
    )
    if (
        edge not in overlay
        or edge in parent_chain
        or edge in root_body.split("photoTimelineHomeContent", 1)[0]
        or ".contentShape(Rectangle())" not in overlay
        or padding_before_gesture
    ):
        violations.append(violation_cls(
            check="timeline.edge_swipe_excludes_header", file=str(hud_path.relative_to(root)), line=1,
            detail="Attach the edge swipe to the content below the header, with its hit shape before any padding.",
        ))
