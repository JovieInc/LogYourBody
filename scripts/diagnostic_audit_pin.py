"""Refresh reviewed audit pins together; never infer approval from candidate bytes."""
import hashlib
import re
import subprocess
from pathlib import Path


AUDIT = "scripts/ios/launch-quality-audit.sh"
WORKFLOW = ".github/workflows/ios-ui-diagnostics.yml"
TESTS = "scripts/tests/test_runner_routing.py"
PIN = re.compile(r"(?m)^( +REVIEWED_AUDIT_SHA256 = ')([0-9a-f]{64})(')$")
TEST_PINS = (
    re.compile(r"(?m)^(    assert module\['REVIEWED_AUDIT_SHA256'\] == hashlib.sha256\(live_audit\).hexdigest\(\) == \(\n        ')([0-9a-f]{64})('\n    \))$"),
    re.compile(r"(?m)^(    expected = ')([0-9a-f]{64})('\n    assert module\['REVIEWED_AUDIT_SHA256'\] == expected)$"),
    re.compile(r'''(?m)^(    assert "REVIEWED_AUDIT_SHA256 = ')([0-9a-f]{64})('\" in source)$'''),
)


def refresh_reviewed_audit(root, reviewed):
    root = Path(root).resolve()
    if not re.fullmatch(r"[0-9a-f]{64}", reviewed):
        raise ValueError("reviewed audit SHA-256 must be 64 lowercase hex characters")
    originals = {}
    for name in (AUDIT, WORKFLOW, TESTS):
        path = root / name
        if not path.is_file() or any(p.is_symlink() for p in (path, *path.parents) if p != root.parent):
            raise ValueError("reviewed audit repair requires regular files: " + name)
        mode = subprocess.run(
            ["git", "ls-files", "--stage", "--", name], cwd=root,
            check=True, capture_output=True, text=True,
        ).stdout.split()
        if len(mode) != 4 or mode[0] not in {"100644", "100755"} or mode[2] != "0":
            raise ValueError("reviewed audit repair requires a resolved regular index entry: " + name)
        staged = subprocess.run(
            ["git", "show", ":" + name], cwd=root, check=True, capture_output=True,
        ).stdout
        if staged != path.read_bytes():
            raise ValueError("stage reviewed audit repair inputs first: " + name)
        if re.search(rb"(?m)^(?:<{2,}|\|{2,}|={2,}|>{2,})(?: |\r?$)", staged):
            raise ValueError("resolve staged conflict markers first: " + name)
        originals[name] = staged
    if hashlib.sha256(originals[AUDIT]).hexdigest() != reviewed:
        raise ValueError("reviewed audit SHA-256 does not match staged source")
    workflow = originals[WORKFLOW].decode()
    pins = PIN.findall(workflow)
    if len(pins) != 1:
        raise ValueError("expected exactly one reviewed audit workflow pin")
    previous = pins[0][1]
    tests = originals[TESTS].decode()
    for pattern in TEST_PINS:
        matches = pattern.findall(tests)
        if len(matches) != 1 or matches[0][1] != previous:
            raise ValueError("reviewed audit regression pins must agree with the workflow")
        tests = pattern.sub(lambda m: m[1] + reviewed + m[3], tests)
    workflow = PIN.sub(lambda m: m[1] + reviewed + m[3], workflow)
    # Validate every input before writing either pin; preserve all unrelated text.
    try:
        (root / WORKFLOW).write_text(workflow)
        (root / TESTS).write_text(tests)
    except OSError:
        for name in (WORKFLOW, TESTS):
            (root / name).write_bytes(originals[name])
        raise
    print("diagnostic-audit: refreshed workflow and regression pins; review and stage explicitly")
