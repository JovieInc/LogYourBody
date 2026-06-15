#!/usr/bin/env python3
"""Static launch-quality checks for LYB iOS UI regressions."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path


@dataclass
class AuditViolation:
    check: str
    file: str
    line: int
    detail: str


def line_number(text: str, index: int) -> int:
    return text.count("\n", 0, index) + 1


def add_pattern_violations(
    *,
    root: Path,
    paths: list[Path],
    pattern: re.Pattern[str],
    check: str,
    detail: str,
    violations: list[AuditViolation],
) -> None:
    for path in paths:
        text = path.read_text(errors="replace")
        for match in pattern.finditer(text):
            violations.append(
                AuditViolation(
                    check=check,
                    file=str(path.relative_to(root)),
                    line=line_number(text, match.start()),
                    detail=detail,
                )
            )


def require_token(
    *,
    root: Path,
    path: Path,
    token: str,
    check: str,
    detail: str,
    violations: list[AuditViolation],
) -> None:
    text = path.read_text(errors="replace")
    if token in text:
        return
    violations.append(
        AuditViolation(
            check=check,
            file=str(path.relative_to(root)),
            line=1,
            detail=detail,
        )
    )


def write_outputs(artifact_dir: Path, violations: list[AuditViolation]) -> None:
    artifact_dir.mkdir(parents=True, exist_ok=True)
    status = "failed" if violations else "passed"
    payload = {
        "schemaVersion": 1,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "status": status,
        "violations": [asdict(violation) for violation in violations],
    }
    (artifact_dir / "launch-ui-regression-audit.json").write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n"
    )

    lines = [
        "# Launch UI Regression Audit",
        "",
        f"- Status: {status.capitalize()}",
        f"- Violations: {len(violations)}",
        "",
    ]

    if violations:
        lines.extend(["## Violations", ""])
        for violation in violations:
            lines.append(
                f"- `{violation.check}` at `{violation.file}:{violation.line}`: "
                f"{violation.detail}"
            )
    else:
        lines.extend(
            [
                "## Covered Contracts",
                "",
                "- Dashboard ScrollViews do not use large fake bottom spacers that create dead over-scroll.",
                "- The removed bottom stats-card hook stays out of app source.",
                "- Body Score share cards expose layout anchors for UI assertions.",
                "- Body Score share cards preserve actual photo aspect defaults instead of forcing one crop.",
                "- Body Score sharing resolves the actual progress photo before presenting the sheet.",
                "- The dashboard avatar visual fills a full-width black stage with transparent assets.",
                "- Dashboard/HUD launch surfaces stay on System B theme colors and real glass material.",
                "- Timeline/Stats swipe navigation changes page on release, not during drag updates.",
                "- Paid users default directly into the timeline HUD without a Statsig or legacy fallback gate.",
            ]
        )

    (artifact_dir / "launch-ui-regression-audit.md").write_text("\n".join(lines) + "\n")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--artifact-dir", type=Path, required=True)
    args = parser.parse_args()

    root = args.root.resolve()
    app_dir = root / "apps/ios/LogYourBody"
    app_swift_files = sorted(app_dir.rglob("*.swift"))
    violations: list[AuditViolation] = []

    add_pattern_violations(
        root=root,
        paths=app_swift_files,
        pattern=re.compile(r"Spacer\s*\(\s*minLength:\s*(?:1[2-9]\d|[2-9]\d{2,})"),
        check="overscroll.no_large_fake_bottom_spacers",
        detail="Use real bottom padding or safe-area insets instead of fake ScrollView content.",
        violations=violations,
    )

    add_pattern_violations(
        root=root,
        paths=app_swift_files,
        pattern=re.compile(r"photo_timeline_hud_stats_button"),
        check="timeline.no_bottom_stats_card",
        detail="Stats must stay in top navigation or swipe navigation, not a bottom switch card.",
        violations=violations,
    )

    share_card = app_dir / "Components/BodyScoreShareCard.swift"
    for token in [
        "body_score_share_photo_visual",
        "body_score_share_avatar_visual",
        "body_score_share_summary",
        "body_score_share_metrics",
        "body_score_share_footer",
        "preferredExportAspect(for: payload.photoImage)",
        ".scaledToFit()",
    ]:
        require_token(
            root=root,
            path=share_card,
            token=token,
            check="share_card.required_layout_anchor",
            detail=f"Missing share-card layout anchor `{token}`.",
            violations=violations,
        )

    dashboard_components = app_dir / "Views/DashboardViewLiquid+Components.swift"
    for token in [
        ".background(theme.colors.background)",
        "padding: 0,",
        "horizontalFillScale: 1.0",
        "renderMode: .fillWidth",
    ]:
        require_token(
            root=root,
            path=dashboard_components,
            token=token,
            check="avatar.full_width_transparent_stage",
            detail=f"Missing avatar full-width hero-stage contract `{token}`.",
            violations=violations,
        )

    system_b_surface_files = [
        app_dir / "Views/DashboardViewLiquid+PhotoTimelineHUD.swift",
        app_dir / "Views/DashboardViewLiquid+PhotoTimelineInsights.swift",
        app_dir / "Views/DashboardViewLiquid+PhotoTimelineAnalytics.swift",
        app_dir / "Views/DashboardViewLiquid+HomeTimelineControls.swift",
        app_dir / "DesignSystem/Organisms/MetricSummaryCard.swift",
    ]
    for path in system_b_surface_files:
        require_token(
            root=root,
            path=path,
            token=".systemBGlassSurface(",
            check="dashboard.system_b_glass_surface",
            detail="Dashboard/HUD cards must use the theme-backed System B glass surface.",
            violations=violations,
        )

    system_b_dashboard_files = [
        app_dir / "Components/DashboardMetricsList.swift",
        app_dir / "DesignSystem/Organisms/MetricSummaryCard.swift",
        app_dir / "Views/DashboardMetricsSection.swift",
        app_dir / "Views/DashboardViewLiquid.swift",
        app_dir / "Views/DashboardViewLiquid+Components.swift",
        app_dir / "Views/DashboardViewLiquid+Glp1MetricCard.swift",
        app_dir / "Views/DashboardViewLiquid+HeroAndActions.swift",
        app_dir / "Views/DashboardViewLiquid+HomeTimelineControls.swift",
        app_dir / "Views/DashboardViewLiquid+MetricViews.swift",
        app_dir / "Views/DashboardViewLiquid+PhotoTimelineAnalytics.swift",
        app_dir / "Views/DashboardViewLiquid+PhotoTimelineHUD.swift",
        app_dir / "Views/DashboardViewLiquid+PhotoTimelineInsights.swift",
    ]
    add_pattern_violations(
        root=root,
        paths=system_b_dashboard_files,
        pattern=re.compile(
            r"Color\.(?:metric|liquid|app|white|black)\b|"
            r"Material\.ultraThinMaterial|"
            r"Color\.metricCard|Color\.metricCardBorder|cardCornerRadius"
        ),
        check="dashboard.system_b_theme_tokens",
        detail="Dashboard launch surfaces should use theme colors/materials instead of legacy color namespaces or fake glass.",
        violations=violations,
    )

    main_tab_view = app_dir / "Views/MainTabView.swift"
    require_token(
        root=root,
        path=main_tab_view,
        token="static func surface() -> PaidAppSurface {\n        .photoTimelineHUD",
        check="routing.timeline_hud_default",
        detail="Paid app default surface must route straight to the timeline HUD for v1.",
        violations=violations,
    )

    add_pattern_violations(
        root=root,
        paths=[main_tab_view],
        pattern=re.compile(r"AnalyticsService\.shared\.isFeatureEnabled|Statsig\.checkGate"),
        check="routing.no_feature_gate_default_surface",
        detail="The v1 paid-app default surface must not depend on a feature gate or legacy fallback.",
        violations=violations,
    )

    require_token(
        root=root,
        path=app_dir / "Views/OptimizedProgressPhotoView.swift",
        token="static func resolvedImage(for urlString: String?) async -> UIImage?",
        check="share_card.actual_photo_resolution",
        detail="Share actions must resolve the actual cached or loaded progress photo before presenting.",
        violations=violations,
    )
    require_token(
        root=root,
        path=app_dir / "Views/DashboardViewLiquid+HomeTimelineControls.swift",
        token="makeBodyScoreSharePayloadResolvingPhoto",
        check="share_card.actual_photo_resolution",
        detail="Dashboard share actions must use the async photo-resolving payload path.",
        violations=violations,
    )

    add_pattern_violations(
        root=root,
        paths=[app_dir / "Views/DashboardViewLiquid+PhotoTimelineHUD.swift"],
        pattern=re.compile(r"\.onChanged\s*\{[^}]*updatePhotoTimelineRootPage", re.DOTALL),
        check="timeline.swipe_release_only",
        detail="Timeline/Stats swipe should settle on release, not mutate root page mid-drag.",
        violations=violations,
    )

    write_outputs(args.artifact_dir, violations)
    if violations:
        print(f"Launch UI regression audit failed with {len(violations)} violation(s).")
        for violation in violations:
            print(f"- {violation.check}: {violation.file}:{violation.line} {violation.detail}")
    else:
        print("Launch UI regression audit passed.")
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())
