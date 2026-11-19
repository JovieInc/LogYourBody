"""Xcode toolchain receipt parsed from the project file."""
from __future__ import annotations

import json
import re

PROJECT_REL = "apps/ios/LogYourBody.xcodeproj/project.pbxproj"
SCHEMA = 1

CONFIG_LIST = re.compile(
    r"(?P<id>[A-Fa-f0-9]+) /\* Build configuration list for (?P<kind>PBXNativeTarget|PBXProject) \"(?P<name>[^\"]+)\" \*/ = \{\s*"
    r"isa = XCConfigurationList;\s*buildConfigurations = \((?P<body>.*?)\);",
    re.S,
)
CONFIG_BLOCK = re.compile(
    r"(?P<id>[A-Fa-f0-9]+) /\* (?P<label>Debug|Release) \*/ = \{\s*"
    r"isa = XCBuildConfiguration;\s*(?P<pre>.*?)buildSettings = \{(?P<body>.*?)\};\s*"
    r"name = (?P<name>Debug|Release);",
    re.S,
)

def parse_settings(body: str) -> dict[str, str]:
    settings: dict[str, str] = {}
    lines = body.splitlines()
    index = 0
    while index < len(lines):
        line = lines[index].strip()
        index += 1
        if not line or line.startswith("//") or "=" not in line:
            continue
        key, rest = line.split("=", 1)
        key = key.strip()
        rest = rest.strip()
        if rest == "(":
            values = []
            while index < len(lines) and lines[index].strip() != ");":
                chunk = lines[index].strip().strip(",").strip().strip('"')
                if chunk:
                    values.append(chunk)
                index += 1
            settings[key] = " ".join(values)
            continue
        settings[key] = rest.rstrip(";").strip().strip('"')
    return settings


def parse_project(text: str) -> list[dict]:
    blocks = {match.group("id"): parse_settings(match.group("body")) for match in CONFIG_BLOCK.finditer(text)}
    lists = []
    for match in CONFIG_LIST.finditer(text):
        configs = re.findall(r"([A-Fa-f0-9]+) /\* (Debug|Release) \*/", match.group("body"))
        lists.append((match.group("kind"), match.group("name"), configs))
    project = {"Debug": {}, "Release": {}}
    targets = []
    for kind, name, configs in lists:
        resolved = {}
        for config_id, label in configs:
            resolved[label] = blocks.get(config_id, {})
        if kind == "PBXProject":
            project = resolved
        else:
            targets.append((name, resolved))
    rows = []
    for name, configs in targets:
        for label in ("Debug", "Release"):
            merged = dict(project.get(label, {}))
            merged.update(configs.get(label, {}))
            rows.append(toolchain_row(name, label, merged))
    return rows


def upcoming_features(settings: dict[str, str]) -> list[str]:
    names = []
    for key, value in settings.items():
        prefix = "SWIFT_UPCOMING_FEATURE_"
        if key.startswith(prefix) and key != prefix and value == "YES":
            names.append(key[len(prefix):])
    flags = settings.get("OTHER_SWIFT_FLAGS", "")
    names.extend(re.findall(r"-enable-upcoming-feature\s+([A-Za-z0-9_]+)", flags))
    return sorted(set(names))


def isolation_setting(settings: dict[str, str]) -> str | None:
    value = settings.get("SWIFT_DEFAULT_ACTOR_ISOLATION")
    if value:
        return value
    flags = settings.get("OTHER_SWIFT_FLAGS", "")
    match = re.search(r"-default-isolation\s+([A-Za-z0-9_]+)", flags)
    return match.group(1) if match else None


def trace_enabled(settings: dict[str, str]) -> bool:
    blob = f"{settings.get('SWIFT_ACTIVE_COMPILATION_CONDITIONS', '')} {settings.get('OTHER_SWIFT_FLAGS', '')}"
    return "LYB_PERF_TRACE" in set(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", blob))


def toolchain_row(target: str, config: str, settings: dict[str, str]) -> dict:
    version = settings.get("SWIFT_VERSION")
    return {
        "target": target,
        "config": config,
        "swift": version,
        "strict": settings.get("SWIFT_STRICT_CONCURRENCY"),
        "isolation": isolation_setting(settings),
        "upcoming": upcoming_features(settings),
        "trace": trace_enabled(settings),
    }


def version_tuple(value: str | None) -> tuple[int, int]:
    if not value:
        return (0, 0)
    parts = []
    for part in value.split("."):
        if part.isdigit():
            parts.append(int(part))
        else:
            break
    if not parts:
        return (0, 0)
    return (parts[0], parts[1] if len(parts) > 1 else 0)


def row_enables_concurrent(row: dict) -> bool:
    if row["isolation"]:
        return True
    if any("CONCURRENT" in name.upper() for name in row["upcoming"]):
        return True
    return version_tuple(row["swift"]) >= (6, 2)


def build_toolchain_receipt(text: str) -> dict:
    rows = sorted(parse_project(text), key=lambda row: (row["target"], row["config"]))
    tuples = {(row["swift"], row["strict"], row["isolation"], tuple(row["upcoming"])) for row in rows}
    agree = len(tuples) == 1 and bool(rows)
    prototype = rows[0] if agree else None
    app_rows = [row for row in rows if row["target"] == "LogYourBody"]
    enabled = bool(app_rows) and all(row_enables_concurrent(row) for row in app_rows)
    formatted = [
        "{target}|{config}|swift={swift}|strict={strict}|isolation={isolation}|upcoming={upcoming}|trace={trace}".format(
            target=row["target"],
            config=row["config"],
            swift=row["swift"] or "",
            strict=row["strict"] or "",
            isolation=row["isolation"] or "",
            upcoming=",".join(row["upcoming"]),
            trace="true" if row["trace"] else "false",
        )
        for row in rows
    ]
    note = "SWIFT_VERSION is the Swift language mode."
    if agree and prototype and prototype["isolation"] is None and not enabled:
        note += " No default-actor-isolation setting is present, so @concurrent is not enabled."
    return {
        "schemaVersion": SCHEMA,
        "kind": "lyb.swift-toolchain-receipt",
        "source": PROJECT_REL,
        "swiftLanguageMode": prototype["swift"] if prototype else None,
        "SWIFT_VERSION": prototype["swift"] if prototype else None,
        "strictConcurrency": prototype["strict"] if prototype else None,
        "defaultActorIsolation": prototype["isolation"] if prototype else None,
        "upcomingFeatures": list(prototype["upcoming"]) if prototype else [],
        "configurationsAgree": agree,
        "concurrentAttributeEnabled": enabled,
        "traceSignpostsEnabled": any(row["trace"] for row in rows),
        "rows": formatted,
        "note": note,
    }


def toolchain_drift_errors(live: dict, committed: dict) -> list[str]:
    if live == committed:
        return []
    return ["toolchain receipt drifted from the Xcode project: " + json.dumps(live, sort_keys=True)]

