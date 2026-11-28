"""Move every current reviewed launch-audit pin from one explicit digest."""
import difflib
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


def assert_staged_project_pin(root, read_staged, project):
    """Refuse stale diagnostic trust before a commit can refresh its source map."""
    tracked = subprocess.run(
        ["git", "ls-files", "-z", "--", project],
        cwd=root, check=True, capture_output=True,
    ).stdout
    if not tracked:
        return
    source = read_staged(root, DIAGNOSTIC_WORKFLOW).decode()
    pins = re.findall(
        r"(?m)^ +'" + re.escape(project) + r"': '([0-9a-f]{64})',$", source,
    )
    if pins != [repository_docs.digest(read_staged(root, project))]:
        raise ValueError(
            "staged diagnostic project pin is stale or ambiguous; review the project diff, "
            "then run python3 scripts/resolve-repository-docs.py "
            "--reviewed-project-sha256 <reviewed-digest>"
        )


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


_DEP_LINE = re.compile(r"^ +'[^']+': '[0-9a-f]{64}',$")
_HUNK_EDGE = re.compile(r"^(?:<{2,}|\|{2,}|={2,}|>{2,})(?: |\r?$)")


def _mask_pins(text, project_pin):
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


def _with_audit(text, digest):
    if digest is None or AUDIT_PIN.search(text) is None:
        return text
    updated, count = AUDIT_PIN.subn(
        lambda match: match.group(1) + digest + match.group(3), text, count=1,
    )
    if count != 1:
        raise ValueError("diagnostic workflow conflict is not limited to the project pin")
    return updated


def _choose_audit(base_audit, ours_audit, theirs_audit, explicit_audit):
    """A one-sided reviewed audit pin follows the parent that changed it."""
    if ours_audit == theirs_audit:
        chosen = ours_audit
    elif ours_audit == base_audit:
        chosen = theirs_audit
    elif theirs_audit == base_audit:
        chosen = ours_audit
    elif explicit_audit is not None:
        chosen = explicit_audit
    else:
        raise ValueError("diagnostic workflow conflict includes divergent reviewed audit pins")
    if explicit_audit is not None and chosen != explicit_audit:
        raise ValueError("reviewed audit SHA-256 does not match the retained pin")
    if chosen is None and explicit_audit is None and ours_audit != theirs_audit:
        raise ValueError("diagnostic workflow conflict is not limited to the project pin")
    return chosen


def _dependency_union(base, ours, theirs):
    """Keep one-sided dependency additions and hash updates; refuse deletions or divergence."""
    def skeleton(text):
        return [line for line in text.splitlines() if not _DEP_LINE.fullmatch(line)]

    def entries(text):
        found = {}
        for line in text.splitlines():
            if not _DEP_LINE.fullmatch(line):
                continue
            key = line.split("': '", 1)[0]
            if key in found:
                return None
            found[key] = line
        return found

    if skeleton(base) != skeleton(ours) or skeleton(base) != skeleton(theirs):
        return None
    base_entries, ours_entries, theirs_entries = entries(base), entries(ours), entries(theirs)
    if base_entries is None or ours_entries is None or theirs_entries is None:
        return None
    extra, replacements = [], {}
    for key in set(base_entries) | set(ours_entries) | set(theirs_entries):
        base_line = base_entries.get(key)
        ours_line = ours_entries.get(key)
        theirs_line = theirs_entries.get(key)
        if ours_line == theirs_line:
            if base_line not in (None, ours_line):
                return None
            continue
        if base_line == ours_line and theirs_line is not None:
            if ours_line is None:
                extra.append(theirs_line)
            else:
                replacements[ours_line] = theirs_line
        elif base_line == theirs_line and ours_line is not None:
            continue
        else:
            return None
    for original, updated in replacements.items():
        ours = ours.replace(original, updated)
    if not extra:
        return ours
    result = ours.splitlines()
    theirs_lines = theirs.splitlines()
    for line in extra:
        index = theirs_lines.index(line)
        inserted = False
        for previous in reversed(theirs_lines[:index]):
            if previous in result:
                result.insert(result.index(previous) + 1, line)
                inserted = True
                break
        if not inserted:
            for following in theirs_lines[index + 1:]:
                if following in result:
                    result.insert(result.index(following), line)
                    inserted = True
                    break
        if not inserted:
            return None
    return "\n".join(result) + ("\n" if ours.endswith("\n") else "")


def _project_hunk_text(text, project_pin):
    """Return the branch side when every conflict hunk is one project-pin line."""
    lines, out, index, saw = text.splitlines(keepends=True), [], 0, False
    while index < len(lines):
        line = lines[index]
        if line[:1] != "<" or not re.match(r"^<{2,}(?: |\r?$)", line):
            if re.match(r"^(?:\|{2,}|={2,}|>{2,})(?: |\r?$)", line):
                raise ValueError("diagnostic workflow conflict is not limited to the project pin")
            out.append(line)
            index += 1
            continue
        saw, index, ours = True, index + 1, None
        for end in "=>":
            chunk = []
            while index < len(lines) and not re.match(rf"^{end}{{2,}}(?: |\r?$)", lines[index]):
                chunk.append(lines[index])
                index += 1
            if index >= len(lines) or len(chunk) != 1 or not project_pin.fullmatch(chunk[0].rstrip("\r\n")):
                raise ValueError("diagnostic workflow conflict is not limited to the project pin")
            ours = chunk[0] if end == "=" else ours
            index += 1
        out.append(ours)
    if not saw:
        raise ValueError("diagnostic workflow conflict is not limited to the project pin")
    return "".join(out)


def _resolve_pin_hunks(text, project_line, audit_line):
    lines, out, index = text.splitlines(keepends=True), [], 0
    while index < len(lines):
        if not re.match(r"^<{2,}(?: |\r?$)", lines[index]):
            if _HUNK_EDGE.match(lines[index]):
                raise ValueError("diagnostic workflow conflict is not limited to the project pin")
            out.append(lines[index])
            index += 1
            continue
        index += 1
        sides = []
        for end in "=>":
            chunk = []
            while index < len(lines) and not re.match(rf"^{end}{{2,}}(?: |\r?$)", lines[index]):
                chunk.append(lines[index])
                index += 1
            if index >= len(lines) or len(chunk) != 1:
                raise ValueError("diagnostic workflow conflict is not limited to the project pin")
            sides.append(chunk[0])
            index += 1
        ours, theirs = (side.rstrip("\r\n") for side in sides)
        newline = "\n" if sides[0].endswith("\n") else ""
        if AUDIT_PIN.fullmatch(ours) and AUDIT_PIN.fullmatch(theirs):
            if audit_line is None:
                raise ValueError("diagnostic workflow conflict is not limited to the project pin")
            out.append(audit_line + newline)
        elif (
            project_line is not None
            and _mask_digest(ours) == _mask_digest(project_line)
            and _mask_digest(theirs) == _mask_digest(project_line)
        ):
            out.append(project_line + newline)
        else:
            raise ValueError("diagnostic workflow conflict is not limited to the project pin")
    return "".join(out)


def _mask_digest(line):
    return re.sub(r"[0-9a-f]{64}", "0" * 64, line, count=1)


def _worktree_matches(worktree, expected, project_line, audit_line):
    if worktree is None or not re.search(r"(?m)^<{2,}(?: |\r?$)", worktree):
        return
    actual = _resolve_pin_hunks(worktree, project_line, audit_line)
    if actual.splitlines() != expected.splitlines():
        raise ValueError("diagnostic workflow conflict is not limited to the project pin")


def conflicted_pin_template(base, ours, theirs, project_pin, explicit_audit=None, worktree=None):
    """Keep branch workflow lines, one-sided dependency lines, and reviewed pins.

    A one-sided reviewed audit pin follows the parent that changed it.
    One-sided dependency lines stay; divergent audit pins need an explicit digest.
    """
    masked = [_mask_pins(text, project_pin) for text in (base, ours, theirs)]
    base_audit, ours_audit, theirs_audit = (item[1] for item in masked)
    chosen = None
    if len({item[0] for item in masked}) == 1:
        chosen = _choose_audit(base_audit, ours_audit, theirs_audit, explicit_audit)
        return _with_audit(ours, chosen)
    union = _dependency_union(*(item[0] for item in masked))
    if union is not None:
        chosen = _choose_audit(base_audit, ours_audit, theirs_audit, explicit_audit)
        expected = _with_audit(union, chosen)
        project_line = project_pin.search(union).group(0)
        audit_line = AUDIT_PIN.search(expected).group(0) if AUDIT_PIN.search(expected) else None
        _worktree_matches(worktree, expected, project_line, audit_line)
        return expected
    project_masked = []
    for text in (base, ours, theirs):
        masked_project, count = project_pin.subn(
            lambda match: match.group(1) + ("0" * 64) + match.group(2), text, count=1,
        )
        if count != 1:
            raise ValueError("diagnostic workflow conflict is not limited to the project pin")
        project_masked.append(masked_project)
    unchanged = 2 if project_masked[0] == project_masked[2] else 1
    if project_masked[0] == project_masked[unchanged]:
        retained = 1 if unchanged == 2 else 2
        if retained == 2 and any(
            tag not in ("equal", "insert")
            for tag, *_ in difflib.SequenceMatcher(
                a=project_masked[0].splitlines(), b=project_masked[2].splitlines(), autojunk=False,
            ).get_opcodes()
        ):
            raise ValueError("diagnostic workflow conflict is not limited to the project pin")
        if worktree is None:
            raise ValueError("diagnostic workflow conflict is not limited to the project pin")
        actual = _project_hunk_text(worktree, project_pin)
        masked_actual, _ = project_pin.subn(
            lambda match: match.group(1) + ("0" * 64) + match.group(2), actual, count=1,
        )
        if masked_actual != project_masked[retained]:
            raise ValueError("diagnostic workflow conflict is not limited to the project pin")
        return (base, ours, theirs)[retained]
    raise ValueError("diagnostic workflow conflict is not limited to the project pin")


def assert_staged_audit(root, expected):
    if not re.fullmatch(r"[0-9a-f]{64}", expected or ""):
        raise ValueError("reviewed audit SHA-256 must be 64 lowercase hex characters")
    if repository_docs.digest(_snapshot(root, DIAGNOSTIC_AUDIT)) != expected:
        raise ValueError("reviewed audit SHA-256 does not match merged source")


def conflicted_routing_text(root, expected):
    """Replace routing-test conflict hunks that differ only by the audit digest."""
    unmerged = subprocess.run(
        ["git", "ls-files", "--unmerged", "--", DIAGNOSTIC_ROUTING_TESTS],
        cwd=root, check=True, capture_output=True, text=True,
    )
    if not unmerged.stdout.strip():
        return None
    path = repository_docs.local(root, DIAGNOSTIC_ROUTING_TESTS)
    lines, out, index = path.read_text().splitlines(keepends=True), [], 0
    while index < len(lines):
        if not re.match(r"^<{2,}(?: |\r?$)", lines[index]):
            if _HUNK_EDGE.match(lines[index]):
                raise ValueError("routing test conflict is not limited to the reviewed audit pin")
            out.append(lines[index])
            index += 1
            continue
        index += 1
        sides = []
        for end in "=>":
            chunk = []
            while index < len(lines) and not re.match(rf"^{end}{{2,}}(?: |\r?$)", lines[index]):
                chunk.append(lines[index])
                index += 1
            if index >= len(lines) or len(chunk) != 1:
                raise ValueError("routing test conflict is not limited to the reviewed audit pin")
            sides.append(chunk[0])
            index += 1
        if _mask_digest(sides[0].rstrip("\r\n")) != _mask_digest(sides[1].rstrip("\r\n")):
            raise ValueError("routing test conflict is not limited to the reviewed audit pin")
        newline = "\n" if sides[0].endswith("\n") else ""
        out.append(_mask_digest(sides[0].rstrip("\r\n")).replace("0" * 64, expected) + newline)
    return "".join(out)


def stage_resolved_pins(root, pin_update, output, resolve_staged, git_bytes):
    workflow, updated, routing_text = pin_update
    path = repository_docs.local(root, workflow)
    original = path.read_bytes()
    if not _MARKER.search(original) and original.decode() != updated:
        raise ValueError(
            "diagnostic pin repair refuses a manually edited workflow; review and stage it explicitly"
        )
    index = git_bytes(root, "ls-files", "--stage", "--", workflow)
    routing_name = DIAGNOSTIC_ROUTING_TESTS
    routing_path = repository_docs.local(root, routing_name)
    routing_original = routing_path.read_bytes() if routing_text is not None else None
    routing_index = git_bytes(root, "ls-files", "--stage", "--", routing_name) if routing_text is not None else b""
    try:
        errors = repository_docs.run(root)
        if errors and errors != ["source projection stale: " + output]:
            raise ValueError("; ".join(errors))
        path.write_bytes(updated.encode())
        names = [workflow]
        if routing_text is not None:
            routing_path.write_text(routing_text)
            names.append(routing_name)
        subprocess.run(["git", "add", "--", *names], cwd=root, check=True)
        resolve_staged(root)
    except (ValueError, OSError, subprocess.CalledProcessError):
        path.write_bytes(original)
        if routing_original is not None:
            routing_path.write_bytes(routing_original)
        subprocess.run(["git", "update-index", "--force-remove", "--", workflow], cwd=root, check=True)
        subprocess.run(["git", "update-index", "--index-info"], cwd=root, input=index, check=True)
        if routing_text is not None:
            subprocess.run(["git", "update-index", "--force-remove", "--", routing_name], cwd=root, check=True)
            subprocess.run(["git", "update-index", "--index-info"], cwd=root, input=routing_index, check=True)
        raise


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
