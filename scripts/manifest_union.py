#!/usr/bin/env python3
"""Union additive shared-lib test wiring during a merge.

The repository-docs resolver keeps this sibling so it stays within the company
500-line ratchet. Unchanged manifest bytes are copied from the branch; only
added test-script tokens and turbo strings are inserted.
"""
import json
import re
import subprocess
from collections import Counter
from pathlib import Path

import repository_docs

MANIFESTS = (
    "packages/shared-lib/package.json",
    "packages/shared-lib/turbo.json",
)
UNION_REFUSAL = "additive manifest union keeps every parent test input"


def _skip(text, index):
    while index < len(text) and text[index] in " \t\r\n":
        index += 1
    return index


def _parse_json_node(text, index):
    index = _skip(text, index)
    if index >= len(text):
        raise ValueError("manifest union expected JSON")
    start, char = index, text[index]
    if char == '"':
        index += 1
        while index < len(text):
            if text[index] == "\\":
                index += 2
                continue
            if text[index] == '"':
                index += 1
                return ("str", json.loads(text[start:index]), start, index)
            index += 1
        raise ValueError("manifest union expected a string")
    if char in "{[":
        closer = "}" if char == "{" else "]"
        index += 1
        items = []
        index = _skip(text, index)
        if index < len(text) and text[index] == closer:
            return ("obj" if char == "{" else "arr", items, start, index + 1)
        while True:
            key = None
            if char == "{":
                key = _parse_json_node(text, index)
                if key[0] != "str":
                    raise ValueError("manifest union expected an object key")
                index = _skip(text, key[3])
                if index >= len(text) or text[index] != ":":
                    raise ValueError("manifest union expected a colon")
                index += 1
            value = _parse_json_node(text, index)
            items.append((key[1], value) if key else value)
            index = _skip(text, value[3])
            if index < len(text) and text[index] == ",":
                index += 1
                continue
            if index < len(text) and text[index] == closer:
                return ("obj" if char == "{" else "arr", items, start, index + 1)
            raise ValueError("manifest union expected " + closer)
    if text.startswith(("true", "false", "null"), index):
        literal = next(item for item in ("true", "false", "null") if text.startswith(item, index))
        return ("lit", json.loads(literal), start, index + len(literal))
    if char == "-" or char.isdigit():
        end = index + 1
        while end < len(text) and text[end] in "0123456789.eE+-":
            end += 1
        return ("lit", json.loads(text[index:end]), start, end)
    raise ValueError("manifest union expected JSON")


def parse_json_spans(text):
    if "\r" in text or re.search(r"(?m)^(?:<{2,}|\|{2,}|={2,}|>{2,})(?: |\r?$)", text):
        raise ValueError(UNION_REFUSAL + ": parent is not clean manifest text")
    node = _parse_json_node(text, 0)
    if _skip(text, node[3]) != len(text):
        raise ValueError("manifest union expected one JSON value")
    return node


def node_value(node):
    if node[0] in {"str", "lit"}:
        return node[1]
    if node[0] == "arr":
        return [node_value(item) for item in node[1]]
    return {key: node_value(value) for key, value in node[1]}


def _subsequence(needle, haystack):
    position = 0
    for item in haystack:
        if position < len(needle) and item == needle[position]:
            position += 1
    return position == len(needle)


def union_strings(base, ours, theirs):
    # Preserved repeated inputs, such as a workflow listed twice, stay in branch order.
    for sequence in (ours, theirs):
        if not _subsequence(base, sequence):
            raise ValueError(UNION_REFUSAL)
    result = list(ours)
    index = {item: position for position, item in enumerate(result)}
    previous = None
    for item in theirs:
        if item in index:
            previous = item
            continue
        insert_at = 0 if previous is None else index[previous] + 1
        result.insert(insert_at, item)
        index = {value: position for position, value in enumerate(result)}
        previous = item
    if set(result) != set(ours) | set(theirs):
        raise ValueError(UNION_REFUSAL)
    return result


def union_json(base, ours, theirs, path=(), union_arrays=False):
    if path == ("scripts", "test"):
        if not all(isinstance(value, str) for value in (base, ours, theirs)):
            raise ValueError(UNION_REFUSAL)
        return " ".join(union_strings(base.split(), ours.split(), theirs.split()))
    if isinstance(base, dict):
        if (
            not isinstance(ours, dict) or not isinstance(theirs, dict)
            or list(base) != list(ours) or list(base) != list(theirs)
        ):
            raise ValueError(UNION_REFUSAL + ": keys changed")
        return {
            key: union_json(base[key], ours[key], theirs[key], path + (key,), union_arrays)
            for key in ours
        }
    if isinstance(base, list) and union_arrays and all(
        isinstance(item, str) for item in (*base, *ours, *theirs)
    ):
        return union_strings(base, ours, theirs)
    if base == ours == theirs:
        return ours
    raise ValueError(UNION_REFUSAL + ": changed " + ".".join(path))


def _rebuild_array(text, node, values):
    _kind, items, start, end = node
    if not items:
        raise ValueError(UNION_REFUSAL + ": empty array")
    encoded = {item[1]: text[item[2]:item[3]] for item in items}
    pieces = [encoded.get(value, json.dumps(value)) for value in values]
    if "\n" not in text[start + 1:end - 1]:
        return "[" + ", ".join(pieces) + "]"
    line_start = text.rfind("\n", 0, items[-1][2]) + 1
    indent = text[line_start:items[-1][2]]
    close_indent = text[text.rfind("\n", 0, end - 1) + 1:end - 1]
    return "[" + "\n" + ",\n".join(indent + piece for piece in pieces) + "\n" + close_indent + "]"


def render_updated(text, node, updated):
    replacements = []

    def walk(current, value):
        if node_value(current) == value:
            return
        if current[0] == "arr" and all(item[0] == "str" for item in current[1]):
            replacements.append((current[2], current[3], _rebuild_array(text, current, value)))
            return
        if current[0] == "str":
            replacements.append((current[2], current[3], json.dumps(value)))
            return
        if current[0] == "obj":
            for key, child in current[1]:
                walk(child, value[key])
            return
        raise ValueError(UNION_REFUSAL + ": cannot render this change")

    walk(node, updated)
    for start, end, replacement in sorted(replacements, reverse=True):
        text = text[:start] + replacement + text[end:]
    return text if text.endswith("\n") else text + "\n"


def _stage_texts(root, name):
    listed = subprocess.run(
        ["git", "ls-files", "--unmerged", "-z", "--", name],
        cwd=root, check=True, capture_output=True,
    ).stdout.decode().strip("\0").split("\0")
    stages = [row.split("\t", 1)[0].split() for row in listed if row]
    if len(stages) != 3 or {row[2] for row in stages if len(row) == 3} != {"1", "2", "3"}:
        raise ValueError("manifest union requires all three unmerged stages")
    if any(row[0] not in {"100644", "100755"} for row in stages):
        raise ValueError("manifest union requires regular files")
    texts = []
    for stage in ("1", "2", "3"):
        shown = subprocess.run(
            ["git", "show", f":{stage}:{name}"], cwd=root, check=True, capture_output=True,
        ).stdout
        try:
            texts.append(shown.decode())
        except UnicodeDecodeError as exc:
            raise ValueError(UNION_REFUSAL + ": manifest is not text") from exc
    return texts


def apply_manifest_union(root):
    root = Path(root).resolve()
    subprocess.run(
        ["git", "rev-parse", "--verify", "MERGE_HEAD"],
        cwd=root, check=True, capture_output=True,
    )
    output = json.loads(repository_docs.local(root, "repository-docs.json").read_text())["output"]
    conflicts = {
        name for name in subprocess.run(
            ["git", "diff", "--name-only", "--diff-filter=U", "-z"],
            cwd=root, check=True, capture_output=True,
        ).stdout.decode().split("\0") if name
    }
    unrelated = sorted(conflicts - {output, *MANIFESTS})
    if unrelated:
        raise ValueError("manifest union refuses unrelated conflicts: " + ", ".join(unrelated))
    planned = []
    for name in MANIFESTS:
        if name not in conflicts:
            continue
        base_text, ours_text, theirs_text = _stage_texts(root, name)
        ours_node = parse_json_spans(ours_text)
        merged = union_json(
            node_value(parse_json_spans(base_text)),
            node_value(ours_node),
            node_value(parse_json_spans(theirs_text)),
            union_arrays=name.endswith("turbo.json"),
        )
        rendered = render_updated(ours_text, ours_node, merged)
        if json.loads(rendered) != merged:
            raise ValueError(UNION_REFUSAL + ": rendered JSON drifted")
        planned.append((name, rendered))
    originals = {
        repository_docs.local(root, name): repository_docs.local(root, name).read_bytes()
        for name, _rendered in planned
    }
    try:
        for name, rendered in planned:
            repository_docs.local(root, name).write_text(rendered)
        if planned:
            subprocess.run(
                ["git", "add", "--", *[name for name, _rendered in planned]],
                cwd=root, check=True,
            )
    except (OSError, subprocess.CalledProcessError):
        for path, original in originals.items():
            path.write_bytes(original)
        raise


def _blob(root, spec):
    shown = subprocess.run(["git", "show", spec], cwd=root, capture_output=True)
    if shown.returncode:
        return None
    try:
        return shown.stdout.decode()
    except UnicodeDecodeError as exc:
        raise ValueError(UNION_REFUSAL + ": manifest is not text") from exc


def _require_parent_inputs(base, ours, theirs, merged, path):
    expected = union_strings(list(base), list(ours), list(theirs))
    if (
        Counter(merged) != Counter(expected)
        or not _subsequence(list(ours), list(merged))
        or not _subsequence(list(theirs), list(merged))
    ):
        location = ".".join(path) or "manifest"
        raise ValueError(UNION_REFUSAL + ": auto-merged " + location)


def _preserved(base, ours, theirs, merged, path):
    if path == ("scripts", "test") and all(
        isinstance(value, str) for value in (base, ours, theirs, merged)
    ):
        if ours != base and theirs != base:
            _require_parent_inputs(
                base.split(), ours.split(), theirs.split(), merged.split(), path,
            )
        return
    if all(isinstance(value, list) for value in (base, ours, theirs, merged)) and all(
        isinstance(item, str) for item in (*base, *ours, *theirs, *merged)
    ):
        if ours != base and theirs != base:
            _require_parent_inputs(base, ours, theirs, merged, path)
        return
    if all(isinstance(value, dict) for value in (base, ours, theirs, merged)):
        for key in set(base) & set(ours) & set(theirs) & set(merged):
            _preserved(base[key], ours[key], theirs[key], merged[key], path + (str(key),))


def assert_auto_merged_parent_inputs(root):
    """An auto-merged manifest must keep every parent test input."""
    root = Path(root).resolve()
    if subprocess.run(
        ["git", "rev-parse", "--verify", "MERGE_HEAD"], cwd=root, capture_output=True,
    ).returncode:
        return
    base_rev = subprocess.run(
        ["git", "merge-base", "HEAD", "MERGE_HEAD"],
        cwd=root, check=True, capture_output=True, text=True,
    ).stdout.strip()
    for name in MANIFESTS:
        unmerged = subprocess.run(
            ["git", "ls-files", "--unmerged", "--", name],
            cwd=root, check=True, capture_output=True, text=True,
        ).stdout
        if unmerged.strip():
            raise ValueError("manifest union requires resolved stages before projection rebuild: " + name)
        ours, theirs, base, merged = (
            _blob(root, spec) for spec in (f"HEAD:{name}", f"MERGE_HEAD:{name}", f"{base_rev}:{name}", f":{name}")
        )
        if None in (ours, theirs, base, merged) or ours == base or theirs == base or ours == theirs:
            continue
        _preserved(
            node_value(parse_json_spans(base)),
            node_value(parse_json_spans(ours)),
            node_value(parse_json_spans(theirs)),
            node_value(parse_json_spans(merged)),
            (),
        )
