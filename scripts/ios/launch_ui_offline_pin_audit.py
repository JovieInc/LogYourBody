#!/usr/bin/env python3
"""Reject a satisfied network path that clears a UI-test offline pin."""

from __future__ import annotations

from pathlib import Path

from launch_ui_timeline_audit import AuditViolation, line_number

_CHECK = "sync.ui_test_offline_pin"
# A satisfied path must not clear a UI-test offline pin.
_DETAIL = "A satisfied path must not clear a UI-test offline pin."
_HANDLER = "self?.handleNetworkPathUpdate(isOnline: path.status == .satisfied)"
_DIRECT_PATH = "self.isOnline = path.status == .satisfied"


def check_ui_test_offline_pin(
    root: Path,
    paths: list[Path],
    violations: list[AuditViolation],
    texts: dict[Path, str] | None = None,
) -> None:
    """UI fixtures pin offline; a later satisfied path must leave that pin in place."""
    del paths
    texts = texts or {}
    sync = root / "apps/ios/LogYourBody/Services/RealtimeSyncManager+Part01.swift"
    manager = root / "apps/ios/LogYourBody/Services/RealtimeSyncManager.swift"
    app = root / "apps/ios/LogYourBody/LogYourBodyApp.swift"
    sync_text = texts.get(sync, "")
    manager_text = texts.get(manager, "")
    app_text = texts.get(app, "")
    handler = sync_text.split("networkMonitor.pathUpdateHandler", 1)[-1].split("func setupAuthListener", 1)[0]
    pinned = (
        _HANDLER in handler
        and _DIRECT_PATH not in sync_text
        and "self.isOnline =" not in handler
        and "guard !usesOfflineUITestFixture else { return }" in manager_text
        and "self.isOnline = Self.online(isOnline)" in manager_text
        and "networkMonitor.cancel()" in manager_text
        and "realtimeSyncManager.applyOfflineUITestFixture()" in app_text
    )
    if not pinned:
        violations.append(AuditViolation(
            check=_CHECK,
            file=str(sync.relative_to(root)),
            line=line_number(sync_text, max(sync_text.find("isOnline"), 0)),
            detail=_DETAIL,
        ))
