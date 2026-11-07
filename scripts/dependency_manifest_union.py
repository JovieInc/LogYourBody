#!/usr/bin/env python3
"""Union conflicted package.json dependency maps during lockfile repair.

Kept beside manifest_union.py so both stay within the company 500-line ratchet.
The repository-docs resolver calls this only from --refresh-lockfile.
"""
import json
import re
import subprocess
from pathlib import Path

import repository_docs
from manifest_union import _stage_texts, node_value, parse_json_spans

_MISSING = object()
_DEPENDENCY_FIELDS = {"dependencies", "devDependencies", "optionalDependencies", "peerDependencies"}
_RANGE = re.compile(r"^([\^~])?(\d+)\.(\d+)\.(\d+)([\-+][0-9A-Za-z.-]+)?$")


def _range_rank(spec):
    match = _RANGE.fullmatch(spec)
    if not match:
        return None
    return (match.group(1) or "=", tuple(int(match.group(i)) for i in (2, 3, 4)), match.group(5) or "")


def _higher_range(left, right):
    a, b = _range_rank(left), _range_rank(right)
    if not a or not b or a[0] != b[0]:
        return None
    if a[0] == "^" and a[1][0] != b[1][0]:
        return None
    if a[0] == "~" and a[1][:2] != b[1][:2]:
        return None
    if a[1] == b[1] and a[2] != b[2]:
        return None
    return left if (a[1], a[2]) >= (b[1], b[2]) else right


def _spec(base, ours, theirs, path):
    if ours == theirs:
        return ours
    if not isinstance(ours, str) or not isinstance(theirs, str):
        raise ValueError("dependency manifest union cannot render " + ".".join(path))
    if base is not _MISSING and ours == base:
        return theirs
    if base is not _MISSING and theirs == base:
        return ours
    winner = _higher_range(ours, theirs)
    if winner is None:
        raise ValueError("dependency manifest union incompatible " + ".".join(path))
    return winner


def _deps(base, ours, theirs, path):
    base, ours, theirs = (value or {} for value in (base, ours, theirs))
    if not all(isinstance(value, dict) for value in (base, ours, theirs)):
        raise ValueError("dependency manifest union expected a map at " + ".".join(path))
    merged = {}
    for key in set(base) | set(ours) | set(theirs):
        child = path + (key,)
        if key in ours and key in theirs:
            merged[key] = _spec(base[key] if key in base else _MISSING, ours[key], theirs[key], child)
        elif key not in base and (key in ours or key in theirs):
            merged[key] = ours[key] if key in ours else theirs[key]
        elif key in ours and key not in theirs and ours[key] == base.get(key):
            continue
        elif key in theirs and key not in ours and theirs[key] == base.get(key):
            continue
        else:
            raise ValueError("dependency manifest union incompatible " + ".".join(child))
    return merged


def _strict(base, ours, theirs, path):
    if ours is _MISSING and theirs is _MISSING:
        return _MISSING
    if ours is _MISSING or theirs is _MISSING:
        kept = theirs if ours is _MISSING else ours
        if base is not _MISSING and kept == base:
            return _MISSING
        raise ValueError("dependency manifest union incompatible " + ".".join(path))
    if ours == theirs or (base is not _MISSING and theirs == base):
        return ours
    if base is not _MISSING and ours == base:
        return theirs
    if all(isinstance(value, dict) for value in (({} if base is _MISSING else base), ours, theirs)):
        return _strict_dict({} if base is _MISSING else base, ours, theirs, path)
    raise ValueError("dependency manifest union incompatible " + ".".join(path))


def _strict_dict(base, ours, theirs, path):
    merged = {}
    for key in set(base) | set(ours) | set(theirs):
        value = _strict(
            base[key] if key in base else _MISSING,
            ours[key] if key in ours else _MISSING,
            theirs[key] if key in theirs else _MISSING,
            path + (key,),
        )
        if value is not _MISSING:
            merged[key] = value
    return merged


def merge_package_values(base, ours, theirs):
    if not all(isinstance(value, dict) for value in (base, ours, theirs)):
        raise ValueError("dependency manifest union expected a package.json object")
    merged = {}
    for key in set(base) | set(ours) | set(theirs):
        if key in _DEPENDENCY_FIELDS:
            value = _deps(base.get(key), ours.get(key), theirs.get(key), (key,))
            if value:
                merged[key] = value
            continue
        value = _strict(
            base[key] if key in base else _MISSING,
            ours[key] if key in ours else _MISSING,
            theirs[key] if key in theirs else _MISSING,
            (key,),
        )
        if value is not _MISSING:
            merged[key] = value
    return merged


def _render_value(text, node, old, new):
    if old == new:
        return text[node[2]:node[3]]
    if node[0] == "str" and isinstance(new, str):
        return json.dumps(new)
    if node[0] == "obj" and isinstance(old, dict) and isinstance(new, dict):
        return _render_object(text, node, old, new)
    raise ValueError("dependency manifest union cannot render this package.json change")


def _render_object(text, node, old, new):
    items = node[1]
    if not items or "\n" not in text[node[2]:node[3]]:
        raise ValueError("dependency manifest union cannot render this package.json object")
    encoded = {
        key: _render_value(text, child, old[key], new[key])
        for key, child in items if key in new
    }
    for key, value in new.items():
        if key in encoded:
            continue
        if isinstance(value, (dict, list)):
            raise ValueError("dependency manifest union cannot render a new object")
        encoded[key] = json.dumps(value)
    order = [key for key, _child in items if key in new]
    for key in sorted(key for key in new if key not in order):
        order.insert(next((index for index, current in enumerate(order) if key < current), len(order)), key)
    sample = next(child for _key, child in items)
    indent = re.match(r"[ \t]*", text[text.rfind("\n", 0, sample[2]) + 1:sample[2]]).group(0)
    close_at = text.rfind("\n", 0, node[3] - 1) + 1
    body = [
        f"{indent}{json.dumps(key)}: {encoded[key]}{',' if index < len(order) - 1 else ''}"
        for index, key in enumerate(order)
    ]
    return "{\n" + "\n".join(body) + "\n" + text[close_at:node[3] - 1] + "}"


def _render_merged_package(text, node, old, new):
    rendered = _render_value(text, node, old, new)
    rendered = rendered if rendered.endswith("\n") else rendered + "\n"
    if json.loads(rendered) != new:
        raise ValueError("dependency manifest union rendered JSON drifted")
    return rendered


def merge_conflicted_dependency_manifests(root):
    """Union conflicted package.json dependency maps. Other conflicts stay untouched."""
    root = Path(root).resolve()
    names = [
        name for name in subprocess.run(
            ["git", "diff", "--name-only", "--diff-filter=U", "-z"],
            cwd=root, check=True, capture_output=True,
        ).stdout.decode().split("\0")
        if name == "package.json" or name.endswith("/package.json")
    ]
    planned = []
    for name in names:
        base_text, ours_text, theirs_text = _stage_texts(root, name)
        ours_node = parse_json_spans(ours_text)
        ours_value = node_value(ours_node)
        merged = merge_package_values(
            node_value(parse_json_spans(base_text)), ours_value, node_value(parse_json_spans(theirs_text)),
        )
        planned.append((name, _render_merged_package(ours_text, ours_node, ours_value, merged)))
    originals = {
        repository_docs.local(root, name): repository_docs.local(root, name).read_bytes()
        for name, _rendered in planned
    }
    index = subprocess.run(
        ["git", "ls-files", "--stage", "--", *names], cwd=root, check=True, capture_output=True,
    ).stdout if names else b""
    try:
        for name, rendered in planned:
            repository_docs.local(root, name).write_text(rendered)
        if names:
            subprocess.run(["git", "add", "--", *names], cwd=root, check=True)
    except (OSError, subprocess.CalledProcessError):
        for path, original in originals.items():
            path.write_bytes(original)
        if names:
            subprocess.run(["git", "update-index", "--force-remove", "--", *names], cwd=root, check=True)
            subprocess.run(["git", "update-index", "--index-info"], cwd=root, input=index, check=True)
        raise

