#!/usr/bin/env python3
"""Union a conflicted Xcode project when both parents only insert lines."""

import difflib
import re
import subprocess
from pathlib import Path

PROJECT = "apps/ios/LogYourBody.xcodeproj/project.pbxproj"
# A conflicted project unions additive file membership from both parents.
REFUSAL = "additive project union keeps both parent file memberships"
MARKER = re.compile(r"(?m)^(?:<{2,}|\|{2,}|={2,}|>{2,})(?: |\r?$)")
MEMBER = re.compile(
    r"(?m)^\t\t([A-Za-z0-9]+) /\* .*? \*/ = \{isa = PBX(?:BuildFile|FileReference);"
)


def _git(root, *args, check=True):
    return subprocess.run(["git", *args], cwd=root, check=check, capture_output=True)


def _stages(root):
    listed = _git(
        root, "ls-files", "--unmerged", "-z", "--", PROJECT,
    ).stdout.decode().strip("\0").split("\0")
    stages = [row.split("\t", 1)[0].split() for row in listed if row]
    if len(stages) != 3 or {row[2] for row in stages if len(row) == 3} != {"1", "2", "3"}:
        raise ValueError(REFUSAL + ": requires a conflicted Xcode project")
    if any(row[0] not in {"100644", "100755"} for row in stages):
        raise ValueError(REFUSAL + ": requires a regular project file")
    texts = []
    for stage in ("1", "2", "3"):
        shown = _git(root, "show", f":{stage}:{PROJECT}").stdout
        try:
            text = shown.decode()
        except UnicodeDecodeError as error:
            raise ValueError(REFUSAL + ": project is not text") from error
        if MARKER.search(text):
            raise ValueError(REFUSAL + ": parent contains conflict markers")
        texts.append(text)
    return texts


def _insertions(base, other):
    inserts = {}
    for tag, start, _end, first, last in difflib.SequenceMatcher(
        a=base, b=other, autojunk=False,
    ).get_opcodes():
        if tag == "equal":
            continue
        if tag != "insert":
            raise ValueError(REFUSAL + ": parent changed an existing project line")
        inserts[start] = other[first:last]
    return inserts


def union_project_text(base, ours, theirs):
    """Keep every inserted line. Refuse an edit, deletion, or duplicate membership."""
    base_lines = base.splitlines(keepends=True)
    ours_at = _insertions(base_lines, ours.splitlines(keepends=True))
    theirs_at = _insertions(base_lines, theirs.splitlines(keepends=True))
    merged = []
    for index in range(len(base_lines) + 1):
        branch_lines = list(ours_at.get(index, ()))
        merged.extend(branch_lines)
        seen = set(branch_lines)
        for line in theirs_at.get(index, ()):
            if line not in seen:
                merged.append(line)
        if index < len(base_lines):
            merged.append(base_lines[index])
    text = "".join(merged)
    if MARKER.search(text):
        raise ValueError(REFUSAL + ": union contains conflict markers")
    ids = MEMBER.findall(text)
    duplicates = sorted({item for item in ids if ids.count(item) > 1})
    if duplicates:
        raise ValueError(REFUSAL + ": duplicate file membership " + ", ".join(duplicates))
    base_ids = set(MEMBER.findall(base))
    added = set()
    for parent in (ours, theirs):
        added.update(set(MEMBER.findall(parent)) - base_ids)
    missing = sorted(added - set(ids))
    if missing:
        raise ValueError(
            REFUSAL + ": merged project dropped a parent file: " + ", ".join(missing),
        )
    return text


def apply_project_union(root):
    root = Path(root).resolve()
    if _git(root, "rev-parse", "--verify", "MERGE_HEAD", check=False).returncode:
        raise ValueError(REFUSAL + ": requires an active merge")
    path = root / PROJECT
    if any(parent.is_symlink() for parent in (path, *path.parents) if parent != root.parent):
        raise ValueError(REFUSAL + ": refuses symlinks")
    merged = union_project_text(*_stages(root))
    original = path.read_bytes() if path.exists() else None
    index = _git(root, "ls-files", "--stage", "--", PROJECT).stdout
    try:
        path.write_text(merged)
        _git(root, "add", "--", PROJECT)
    except (OSError, subprocess.CalledProcessError):
        if original is None:
            path.unlink(missing_ok=True)
        else:
            path.write_bytes(original)
        _git(root, "update-index", "--force-remove", "--", PROJECT)
        subprocess.run(
            ["git", "update-index", "--index-info"], cwd=root, input=index, check=True,
        )
        raise
    # The reviewed diagnostic digest stays an explicit later input.
    print("repository-docs: staged additive project union")
