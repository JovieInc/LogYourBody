#!/usr/bin/env python3
"""Union additive shared-lib test wiring and resolve correction ledgers during a merge.

The repository-docs resolver keeps this sibling so it stays within the company
500-line ratchet. Unchanged manifest bytes are copied from the branch; only
added test-script tokens and turbo strings are inserted.
"""
import json
import re
import subprocess
from collections import Counter
from contextlib import contextmanager
from pathlib import Path

import repository_docs
from json_union import _skip, _parse_json_node

MANIFESTS = (
    "packages/shared-lib/package.json",
    "packages/shared-lib/turbo.json",
)
# Additive launch-audit sibling registrations keep every parent export.
AUDIT_REGISTRATIONS = (
    "scripts/ios/launch-ui-regression-audit.py",
    "scripts/ios/test_launch_ui_regression_audit.py",
    "packages/shared-lib/src/launch-ui-regression-audit.test.ts",
)
# The correction ledger has its own resolver and must not deadlock manifest union.
LEDGER = "packages/shared-lib/corrections.json"
UNION_REFUSAL = "additive manifest union keeps every parent test input"
_HUNK = re.compile(r"^<<<<<<<[^\n]*\n(.*?\n?)=======\n(.*?\n?)>>>>>>>[^\n]*\n", re.M | re.S)
_TRIPLE = re.compile(r'\(\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,\s*"([^"]+)"\s*\)')
_PY_LIST = re.compile(
    r"\[item\[0\] for item in AUDIT\._AUDIT_SIBLINGS\],\s*\[(.*?)\]",
    re.S,
)
_TS_LIST = re.compile(r"for \(const input of \[(.*?)\]", re.S)


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


def _sibling_triples(text):
    match = re.search(r"_AUDIT_SIBLINGS = \((.*?)\n\)", text, re.S)
    triples = [tuple(item) for item in _TRIPLE.findall(match.group(1))] if match else []
    if not triples:
        raise ValueError(UNION_REFUSAL + ": missing audit siblings")
    return triples


def _union_triples(base_text, ours_text, theirs_text):
    base, ours, theirs = (_sibling_triples(text) for text in (base_text, ours_text, theirs_text))
    by_name = {}
    for item in (*base, *ours, *theirs):
        previous = by_name.setdefault(item[0], item)
        if previous != item:
            raise ValueError(UNION_REFUSAL + ": sibling identity diverged")
    names = union_strings(
        [item[0] for item in base], [item[0] for item in ours], [item[0] for item in theirs],
    )
    return [by_name[name] for name in names]


def _render_siblings(triples):
    rows = "\n".join(
        f'    ("{name}", "{filename}", "{export}"),' for name, filename, export in triples
    )
    exports = ",\n".join(f"    {export}" for _name, _filename, export in triples)
    return (
        "_AUDIT_SIBLINGS = (\n"
        f"{rows}\n"
        ")\n(\n"
        f"{exports},\n"
        ") = [_load_sibling(*sibling) for sibling in _AUDIT_SIBLINGS]\n"
    )


def _quoted_names(text, pattern):
    match = pattern.search(text)
    if not match:
        raise ValueError(UNION_REFUSAL + ": missing sibling name list")
    inner = match.group(1)
    names = re.findall(r"""(['"])([^'"]+)\1""", inner)
    if not names and inner.strip():
        raise ValueError(UNION_REFUSAL + ": sibling name list is not quoted strings")
    quotes = {quote for quote, _name in names}
    if len(quotes) > 1:
        raise ValueError(UNION_REFUSAL + ": mixed sibling quote styles")
    return [name for _quote, name in names]


def _resolve_audit_python(working, triples):
    """Replace the sibling block and union export calls. Other hunks refuse."""
    exports = {export for _name, _filename, export in triples}
    start = working.find("_AUDIT_SIBLINGS = (")
    closer = working.find(">>>>>>>", start)
    if start < 0 or closer < 0 or "<<<<<<<" in working[:start]:
        raise ValueError(UNION_REFUSAL + ": audit registration conflict is not the sibling block")
    end = working.find("\n", closer)
    if end < 0:
        raise ValueError(UNION_REFUSAL + ": audit registration conflict is not the sibling block")
    merged = working[:start] + _render_siblings(triples) + working[end + 1:]

    def call_union(match):
        def calls(side):
            rows = []
            for line in side.splitlines():
                if not line.strip():
                    continue
                found = re.fullmatch(r"\s*([A-Za-z_][A-Za-z0-9_]*)\(.*\)\s*", line)
                if not found or found.group(1) not in exports:
                    raise ValueError(UNION_REFUSAL + ": audit registration conflict is not additive")
                rows.append(line)
            return rows

        lines = calls(match.group(1))
        for line in calls(match.group(2)):
            if line not in lines:
                lines.append(line)
        return "\n".join(lines) + ("\n" if lines else "")

    result = _HUNK.sub(call_union, merged)
    if re.search(r"^(?:<<<<<<<|=======|>>>>>>>)", result, re.M):
        raise ValueError(UNION_REFUSAL + ": audit registration conflict is not additive")
    missing = [export for export in exports if f"{export}(" not in result]
    if missing:
        raise ValueError(UNION_REFUSAL + ": missing sibling call " + ", ".join(missing))
    return result


def _resolve_quoted_list(working, pattern, names, quote):
    match = pattern.search(working)
    if not match:
        raise ValueError(UNION_REFUSAL + ": missing sibling name list")
    if not names:
        raise ValueError(UNION_REFUSAL + ": sibling name list is empty")
    hunks = list(_HUNK.finditer(working))
    if not hunks or any(
        hunk.start() < match.start(1) or hunk.end() > match.end(1) for hunk in hunks
    ):
        raise ValueError(UNION_REFUSAL + ": sibling registration conflict is not additive")
    indent = "    "
    for line in match.group(1).splitlines():
        quoted = re.match(r"""^(\s*)(['"])""", line)
        if quoted:
            indent = quoted.group(1)
            break
    close = ""
    trailing = re.search(r"\n([ \t]*)$", match.group(1))
    if trailing:
        close = trailing.group(1)
    lead = "\n" if match.group(1).startswith("\n") else ""
    rendered = lead + "\n".join(f"{indent}{quote}{name}{quote}," for name in names) + "\n" + close
    return working[:match.start(1)] + rendered + working[match.end(1):]


def _resolve_registration(root, name):
    base_text, ours_text, theirs_text = _stage_texts(root, name)
    working = repository_docs.local(root, name).read_text()
    if name.endswith("launch-ui-regression-audit.py"):
        return _resolve_audit_python(working, _union_triples(base_text, ours_text, theirs_text))
    pattern = _PY_LIST if name.endswith("test_launch_ui_regression_audit.py") else _TS_LIST
    ours_names = _quoted_names(ours_text, pattern)
    names = union_strings(
        _quoted_names(base_text, pattern),
        ours_names,
        _quoted_names(theirs_text, pattern),
    )
    quote = re.search(r"""(['"])[^'"]+\1""", pattern.search(ours_text).group(1)).group(1)
    return _resolve_quoted_list(working, pattern, names, quote)


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
    planned = []
    for name in AUDIT_REGISTRATIONS:
        if name in conflicts:
            planned.append((name, _resolve_registration(root, name)))
    unrelated = sorted(conflicts - {output, *MANIFESTS, LEDGER, *AUDIT_REGISTRATIONS})
    if unrelated:
        raise ValueError("manifest union refuses unrelated conflicts: " + ", ".join(unrelated))
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


def projection_is_unmerged(root, output):
    result = subprocess.run(
        ["git", "ls-files", "--unmerged", "--", output],
        cwd=root, check=True, capture_output=True, text=True,
    )
    return bool(result.stdout.strip())


@contextmanager
def restore_dependency_artifacts_on_failure(root, output):
    paths = [repository_docs.local(root, name) for name in ("pnpm-lock.yaml", output)]
    originals = {path: path.read_bytes() if path.exists() else None for path in paths}
    try:
        yield
    except (ValueError, OSError, subprocess.CalledProcessError):
        # Failed dependency repairs restore both artifacts, including staging failures.
        for path, original in originals.items():
            if original is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(original)
        raise


def merge_ledger(root, resolve_staged, staged_bytes, git_bytes):
    """Refresh the staged projection before the parent-preserving ledger resolver."""
    root = Path(root).resolve()
    git_bytes(root, "rev-parse", "--verify", "MERGE_HEAD")
    config = json.loads(staged_bytes(root, "repository-docs.json"))
    output = config["output"]
    conflicts = set(git_bytes(
        root, "diff", "--name-only", "--diff-filter=U", "--relative", "-z",
    ).decode().split("\0")) - {"", output, LEDGER}
    if conflicts:
        raise ValueError("resolve source conflicts first: " + ", ".join(sorted(conflicts)))
    path = repository_docs.local(root, output)
    original = path.read_bytes() if path.exists() else None
    index = git_bytes(root, "ls-files", "--stage", "--", output)
    # Rendering refusals preserve concurrent projection edits; only roll back our completed render.
    resolve_staged(root)
    try:
        subprocess.run(
            ["node", str(Path(__file__).with_name("correction-classifier.mjs")),
             "--resolve-merge", str(root), "--stage"], cwd=root, check=True,
        )
    except (ValueError, OSError, subprocess.CalledProcessError):
        # A refused ledger repair restores the projection and its conflict stages.
        if original is None:
            path.unlink(missing_ok=True)
        else:
            path.write_bytes(original)
        subprocess.run(["git", "update-index", "--force-remove", "--", output], cwd=root, check=True)
        subprocess.run(["git", "update-index", "--index-info"], cwd=root, input=index, check=True)
        raise
