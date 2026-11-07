"""Dated-stats fixture checks for the launch UI regression audit.

Extracted so the parent audit stays within the company 500-line ratchet.
The audit loads this sibling by path.

dated_stats.fixture_survives_path_and_account
"""

from __future__ import annotations

import re
from pathlib import Path


def _function_body(source: str, name: str) -> str:
    match = re.search(rf"func {re.escape(name)}\b", source)
    if match is None:
        return ""
    start = source.find("{", match.end())
    if start < 0:
        return ""
    depth = 0
    for index in range(start, len(source)):
        character = source[index]
        if character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return source[start:index + 1]
    return ""


def _violation(root: Path, path: Path, check: str, detail: str, violation_cls):
    return violation_cls(
        check=check, file=str(path.relative_to(root)), line=1, detail=detail,
    )


def check_dated_stats_fixture(root: Path, texts: dict, violations: list, violation_cls) -> None:
    """Keep an empty Stats fixture offline and on the analytics page."""
    app = root / "apps/ios/LogYourBody"
    sync_path = app / "Services/RealtimeSyncManager.swift"
    part_path = app / "Services/RealtimeSyncManager+Part01.swift"
    dashboard_path = app / "Views/DashboardViewLiquid.swift"
    dated_path = app / "Services/DatedTimelineUI.swift"
    sync = texts[sync_path]
    part = texts[part_path]
    dashboard = texts[dashboard_path]
    dated = texts[dated_path]

    handler = part.split("networkMonitor.pathUpdateHandler", 1)[-1].split("func setupAuthListener", 1)[0]
    online = _function_body(sync, "online")
    fixture_list = sync.split("static let offlineUITestFixtures", 1)[-1].split("]", 1)[0]
    offline_ok = (
        "self.isOnline = Self.online(path.status == .satisfied)" in handler
        and "self.isOnline = path.status == .satisfied" not in handler
        and "guard pathSatisfied else { return false }" in online
        and "offlineUITestFixtures.contains" in online
        and "return !fixtureForcesOffline" in online
        and "return pathSatisfied" not in online
        and '"-lybUITestPhotoTimelineHUDFixture"' in fixture_list
    )
    if not offline_ok:
        violations.append(_violation(
            root, part_path, "dated_stats.offline_survives_path",
            "A satisfied path must not undo a paid UI fixture that forced offline.",
            violation_cls,
        ))

    account = dashboard.split(".onChange(of: authManager.captureAccountSession())", 1)[-1].split(
        ".onChange(of: selectedRange)", 1
    )[0]
    page = _function_body(dated, "pageAfterAccountChange")
    analytics_ok = (
        "selectedPhotoTimelineRootPage = Self.pageAfterAccountChange()" in account
        and "selectedPhotoTimelineRootPage = .timeline" not in account
        and "#if DEBUG" in page
        and 'arguments.contains("-lybUITestPhotoTimelineAnalyticsFixture")' in page
        and page.find("return .analytics") != -1
        and page.find("return .analytics") < page.find("return .timeline")
    )
    if not analytics_ok:
        violations.append(_violation(
            root, dashboard_path, "dated_stats.analytics_survives_account",
            "The analytics fixture must stay on Stats when the account session is published.",
            violation_cls,
        ))
