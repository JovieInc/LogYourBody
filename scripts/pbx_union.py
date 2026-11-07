#!/usr/bin/env python3
"""Union or verify an Xcode project when both parents only insert lines."""

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
    if not _git(root, "ls-files", "--unmerged", "--", PROJECT).stdout:
        # Verify auto-merged projects against the same immutable additive parent union.
        entries = _git(root, "ls-files", "--stage", "-z", "--", PROJECT).stdout.strip(b"\0").split(b"\0")
        metadata = entries[0].split(b"\t", 1)[0].split()
        if len(entries) != 1 or len(metadata) != 3 or metadata[0] not in {b"100644", b"100755"} or metadata[2] != b"0":
            raise ValueError(REFUSAL + ": requires a regular stage-zero project")
        base = _git(root, "merge-base", "--all", "HEAD", "MERGE_HEAD").stdout.decode().splitlines()
        if len(base) != 1:
            raise ValueError(REFUSAL + ": requires one immutable merge base")
        parents = [
            _git(root, "show", f"{rev}:{PROJECT}").stdout.decode()
            for rev in (base[0], "HEAD", "MERGE_HEAD")
        ]
        expected = union_project_text(*parents).encode()
        staged = _git(root, "show", ":" + PROJECT).stdout
        if staged != expected:
            raise ValueError(REFUSAL + ": staged project differs from additive parent union")
        if path.read_bytes() != staged:
            raise ValueError(REFUSAL + ": unstaged project edits")
        print("repository-docs: verified additive project union")
        return
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


PBX_PLACEMENT = re.compile(r"(?m)^\t\t\t\t([A-Za-z0-9]+) /\* .*? \*/,")


def _project_membership(text):
    return set(MEMBER.findall(text)), set(PBX_PLACEMENT.findall(text))


def assert_merged_project_keeps_parent_files(root, project):
    """A merged diagnostic project must keep every parent file membership."""
    # A parent group or build-phase entry must remain even when its definition survived.
    if subprocess.run(
        ["git", "rev-parse", "--verify", "MERGE_HEAD"], cwd=root, capture_output=True,
    ).returncode:
        raise ValueError("diagnostic pin repair requires an active merge")
    base_rev = subprocess.run(
        ["git", "merge-base", "HEAD", "MERGE_HEAD"],
        cwd=root, check=True, capture_output=True, text=True,
    ).stdout.strip()

    def blob(spec):
        try:
            return _git(root, "show", spec).stdout.decode()
        except subprocess.CalledProcessError as error:
            raise ValueError("diagnostic pin repair cannot read " + spec) from error
        except UnicodeDecodeError as error:
            raise ValueError("diagnostic project is not text: " + spec) from error

    base_defs, base_rows = _project_membership(blob(f"{base_rev}:{PROJECT}"))
    added_defs, added_rows, parent_sources = set(), set(), []
    for parent in ("HEAD", "MERGE_HEAD"):
        source = blob(f"{parent}:{PROJECT}")
        parent_sources.append(source)
        defs, rows = _project_membership(source)
        added_defs.update(defs - base_defs)
        added_rows.update(rows - base_rows)
    try:
        merged = project.decode()
        merged_defs, merged_rows = _project_membership(merged)
    except UnicodeDecodeError as error:
        raise ValueError("diagnostic project is not text") from error
    missing = sorted((added_defs - merged_defs) | (added_rows - merged_rows))
    references = [
        identifier for identifier in sorted(added_defs)
        if len(re.findall(r"\b" + re.escape(identifier) + r"\b", merged))
        < max(len(re.findall(r"\b" + re.escape(identifier) + r"\b", source)) for source in parent_sources)
    ]
    # Placement rows and reference counts both survive a merged diagnostic project.
    if missing or references:
        detail = []
        if missing:
            detail.append("merged project dropped a parent file: " + ", ".join(missing))
        if references:
            detail.append("merged project dropped a parent file reference: " + ", ".join(references))
        raise ValueError("; ".join(detail))
