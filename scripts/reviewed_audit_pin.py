"""Move every current reviewed launch-audit pin from one explicit digest."""
import re
import subprocess

import repository_docs

DIAGNOSTIC_AUDIT = "scripts/ios/launch-quality-audit.sh"
DIAGNOSTIC_WORKFLOW = ".github/workflows/ios-ui-diagnostics.yml"
DIAGNOSTIC_ROUTING_TESTS = "scripts/tests/test_runner_routing.py"
AUDIT_PIN = re.compile(
    r"(?m)^( +REVIEWED_AUDIT_SHA256 = ')([0-9a-f]{64})(')$"
)
_MARKER = re.compile(rb"(?m)^(?:<{2,}|\|{2,}|={2,}|>{2,})(?: |\r?$)")


def _staged_bytes(root, name):
    return subprocess.run(
        ["git", "show", ":" + name], cwd=root, check=True, capture_output=True,
    ).stdout


def _snapshot(root, name):
    path = root / name
    if any(parent.is_symlink() for parent in (path, *path.parents) if parent != root.parent):
        raise ValueError("reviewed audit repair refuses symlinks: " + name)
    data = repository_docs.local(root, name).read_bytes()
    if _staged_bytes(root, name) != data:
        raise ValueError("stage reviewed audit and pin edits first: " + name)
    if _MARKER.search(data):
        raise ValueError("resolve staged conflict markers first: " + name)
    return data


def reviewed_audit_pins(root, expected):
    """Replace the workflow pin and each current routing-test copy."""
    if not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise ValueError("reviewed audit SHA-256 must be 64 lowercase hex characters")
    if repository_docs.digest(_snapshot(root, DIAGNOSTIC_AUDIT)) != expected:
        raise ValueError("reviewed audit SHA-256 does not match merged source")
    try:
        workflow = _snapshot(root, DIAGNOSTIC_WORKFLOW).decode()
        tests = _snapshot(root, DIAGNOSTIC_ROUTING_TESTS).decode()
    except UnicodeDecodeError as error:
        raise ValueError("reviewed audit pins are not text") from error
    matches = list(AUDIT_PIN.finditer(workflow))
    if len(matches) != 1:
        raise ValueError("expected exactly one reviewed audit pin")
    quoted = "'" + matches[0].group(2) + "'"
    if quoted not in tests:
        raise ValueError("reviewed audit pin is absent from the routing tests")
    updated_workflow, count = AUDIT_PIN.subn(
        lambda match: match.group(1) + expected + match.group(3), workflow, count=1,
    )
    if count != 1:
        raise ValueError("expected exactly one reviewed audit pin")
    updated_tests = tests.replace(quoted, "'" + expected + "'")
    if quoted != "'" + expected + "'" and quoted in updated_tests:
        raise ValueError("reviewed audit pin replacement was partial")
    return [
        (DIAGNOSTIC_WORKFLOW, updated_workflow),
        (DIAGNOSTIC_ROUTING_TESTS, updated_tests),
    ]


def conflicted_pin_template(base, ours, theirs, project_pin):
    """Keep a one-sided reviewed audit pin while the project pin stays explicit.

    A one-sided reviewed audit pin follows the parent that changed it.
    Divergent reviewed audit pins stay unresolved.
    """
    def mask(text):
        masked, count = project_pin.subn(
            lambda match: match.group(1) + ("0" * 64) + match.group(2), text, count=1,
        )
        if count != 1:
            raise ValueError("diagnostic workflow conflict is not limited to the project pin")
        audits = list(AUDIT_PIN.finditer(masked))
        if len(audits) > 1:
            raise ValueError("diagnostic workflow conflict is not limited to the project pin")
        audit = audits[0].group(2) if audits else None
        if audit is not None:
            masked = AUDIT_PIN.sub(
                lambda match: match.group(1) + ("0" * 64) + match.group(3), masked, count=1,
            )
        return masked, audit

    masked = [mask(text) for text in (base, ours, theirs)]
    if len({item[0] for item in masked}) != 1:
        raise ValueError("diagnostic workflow conflict is not limited to the project pin")
    base_audit, ours_audit, theirs_audit = (item[1] for item in masked)
    if ours_audit == theirs_audit:
        return ours
    if ours_audit == base_audit:
        chosen = theirs_audit
    elif theirs_audit == base_audit:
        chosen = ours_audit
    else:
        raise ValueError("diagnostic workflow conflict includes divergent reviewed audit pins")
    if chosen is None:
        raise ValueError("diagnostic workflow conflict is not limited to the project pin")
    updated, count = AUDIT_PIN.subn(
        lambda match: match.group(1) + chosen + match.group(3), ours, count=1,
    )
    if count != 1:
        raise ValueError("diagnostic workflow conflict is not limited to the project pin")
    return updated


def apply_pins(root, expected, resolve_staged):
    updates = reviewed_audit_pins(root, expected)
    originals = []
    try:
        for name, text in updates:
            path = repository_docs.local(root, name)
            originals.append((path, path.read_bytes()))
            path.write_text(text)
        resolve_staged(root, [name for name, _text in updates])
    except (ValueError, OSError, subprocess.CalledProcessError):
        for path, original in originals:
            path.write_bytes(original)
        raise
