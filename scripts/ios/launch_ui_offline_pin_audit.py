#!/usr/bin/env python3
"""Reject a satisfied network path that clears a UI-test offline pin."""

from __future__ import annotations

from pathlib import Path

from launch_ui_timeline_audit import AuditViolation, line_number

_CHECK = "sync.ui_test_offline_pin"
# A satisfied path must not clear a UI-test offline pin.
_DETAIL = "A satisfied path must not clear a UI-test offline pin."
_ASSIGNMENT = (
    "self.isOnline = Self.online(after: path.status, "
    "pinnedOffline: self.pinsOfflineForUITestFixture)"
)
_DECISION = "static func online(after status: NWPath.Status, pinnedOffline: Bool)"


def check_ui_test_offline_pin(
    root: Path,
    paths: list[Path],
    violations: list[AuditViolation],
    texts: dict[Path, str] | None = None,
) -> None:
    """UI fixtures pin offline; later path updates must leave that pin in place."""
    del paths
    texts = texts or {}
    sync = root / "apps/ios/LogYourBody/Services/RealtimeSyncManager+Part01.swift"
    manager = root / "apps/ios/LogYourBody/Services/RealtimeSyncManager.swift"
    app = root / "apps/ios/LogYourBody/LogYourBodyApp.swift"
    sync_text = texts.get(sync, "")
    manager_text = texts.get(manager, "")
    app_text = texts.get(app, "")
    decision = manager_text.split(_DECISION, 1)[-1].split("func pinOfflineForUITestFixture", 1)[0]
    pinned = "if pinnedOffline { return false }" in decision and "return status == .satisfied" in decision
    if (
        _ASSIGNMENT not in sync_text
        or "self.isOnline = path.status == .satisfied" in sync_text
        or not pinned
        or "realtimeSyncManager.pinOfflineForUITestFixture()" not in app_text
    ):
        violations.append(AuditViolation(
            check=_CHECK,
            file=str(sync.relative_to(root)),
            line=line_number(sync_text, max(sync_text.find("isOnline"), 0)),
            detail=_DETAIL,
        ))
