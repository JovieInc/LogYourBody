"""Propose additive JSON merges from immutable Git index stages without writing."""
import json
import re
import subprocess
from pathlib import Path

import repository_docs


def _unmerged_texts(root, name, kind):
    """Return base, ours, and theirs for one unmerged regular file. Never writes."""
    root = Path(root).resolve()
    repository_docs.local(root, name)

    def git(*args):
        return subprocess.run(
            ["git", *args], cwd=root, check=True, capture_output=True, text=True,
        ).stdout

    git("rev-parse", "--verify", "MERGE_HEAD")
    entries = git("ls-files", "--unmerged", "-z", "--", name).strip("\0").split("\0")
    stages = [entry.split("\t", 1)[0].split() for entry in entries if entry]
    if len(stages) != 3 or {row[2] for row in stages if len(row) == 3} != {"1", "2", "3"}:
        raise ValueError(kind + " requires all three unmerged stages")
    if any(row[0] not in {"100644", "100755"} for row in stages):
        raise ValueError(kind + " requires regular indexed files")
    blobs = [git("show", f":{stage}:{name}") for stage in (1, 2, 3)]
    for source in blobs:
        if re.search(r"(?m)^(?:<{2,}|\|{2,}|={2,}|>{2,})(?: |\r?$)", source):
            raise ValueError(kind + " refuses conflict markers in a parent")
    return blobs


def _json_token(value):
    return json.dumps(value, sort_keys=True, ensure_ascii=False)


def _insert_absent(spine, incoming):
    """Keep spine order and insert incoming values that spine does not already contain."""
    tokens = [_json_token(item) for item in spine]
    index = {token: position for position, token in enumerate(tokens)}
    if len(index) != len(spine) or len({_json_token(item) for item in incoming}) != len(incoming):
        raise ValueError("json union refuses duplicate values")
    pending = []
    inserts = {}
    for item in incoming:
        token = _json_token(item)
        if token in index:
            if pending:
                inserts.setdefault(index[token], []).extend(pending)
                pending = []
        else:
            pending.append(item)
    if pending:
        inserts.setdefault(len(spine), []).extend(pending)
    merged = []
    for position, item in enumerate(spine):
        merged.extend(inserts.get(position, []))
        merged.append(item)
    merged.extend(inserts.get(len(spine), []))
    return merged


def _merge_sequences(spine, incoming):
    """Keep the maximum multiplicity, spine order, and incoming-only values at their anchor."""
    target = {}
    for item in spine:
        token = _json_token(item)
        target[token] = target.get(token, 0) + 1
    incoming_counts = {}
    for item in incoming:
        token = _json_token(item)
        incoming_counts[token] = incoming_counts.get(token, 0) + 1
    for token, count in incoming_counts.items():
        if count > target.get(token, 0):
            target[token] = count
    emitted = {}
    result = []
    index = 0

    def emit_spine_through(match):
        nonlocal index
        while index < len(spine):
            current = spine[index]
            index += 1
            token = _json_token(current)
            if emitted.get(token, 0) < target[token]:
                result.append(current)
                emitted[token] = emitted.get(token, 0) + 1
            if current == match:
                return

    for item in incoming:
        token = _json_token(item)
        if emitted.get(token, 0) >= target[token]:
            continue
        if any(spine[position] == item for position in range(index, len(spine))):
            emit_spine_through(item)
        else:
            result.append(item)
            emitted[token] = emitted.get(token, 0) + 1
    while index < len(spine):
        current = spine[index]
        index += 1
        token = _json_token(current)
        if emitted.get(token, 0) < target[token]:
            result.append(current)
            emitted[token] = emitted.get(token, 0) + 1
    return result


def _union_added(ours, theirs):
    if ours == theirs:
        return ours
    if isinstance(ours, dict) and isinstance(theirs, dict):
        return _union_object({}, ours, theirs)
    if isinstance(ours, list) and isinstance(theirs, list):
        return _union_list([], ours, theirs)
    raise ValueError("json union refuses a conflicting addition")


def _union_object(base, ours, theirs):
    for key in base:
        if key not in ours or key not in theirs:
            raise ValueError("json union refuses a deletion: " + key)
    merged = {}
    for key in _insert_absent(list(ours), list(theirs)):
        if key in ours and key in theirs:
            merged[key] = (
                _union_value(base[key], ours[key], theirs[key])
                if key in base else _union_added(ours[key], theirs[key])
            )
        else:
            merged[key] = ours[key] if key in ours else theirs[key]
    return merged


def _new_duplicate(base, side):
    base_counts = {}
    for item in base:
        token = _json_token(item)
        base_counts[token] = base_counts.get(token, 0) + 1
    seen = {}
    for item in side:
        token = _json_token(item)
        seen[token] = seen.get(token, 0) + 1
        if seen[token] > 1 and seen[token] > base_counts.get(token, 0):
            return True
    return False


def _union_list(base, ours, theirs):
    for sequence in (base, ours, theirs):
        if not all(isinstance(item, (str, int, float, bool, type(None))) for item in sequence):
            raise ValueError("json union refuses non-scalar list edits")
        if _new_duplicate(base, sequence):
            raise ValueError("json union refuses duplicate list values")

    def keeps_base(side):
        cursor = 0
        for item in side:
            if cursor < len(base) and item == base[cursor]:
                cursor += 1
        if cursor != len(base):
            raise ValueError("json union refuses list deletions or reorders")

    keeps_base(ours)
    keeps_base(theirs)
    return _merge_sequences(ours, theirs)


def _union_value(base, ours, theirs):
    if ours == theirs:
        return ours
    if isinstance(base, dict) and isinstance(ours, dict) and isinstance(theirs, dict):
        return _union_object(base, ours, theirs)
    if isinstance(base, list) and isinstance(ours, list) and isinstance(theirs, list):
        return _union_list(base, ours, theirs)
    raise ValueError("json union refuses a conflicting replacement")


def _render_json(value, level=0):
    """Match the repository's compact short arrays and expanded longer ones."""
    pad = "  " * level
    if isinstance(value, dict):
        if not value:
            return "{}"
        rows = [f"{pad}  {json.dumps(key, ensure_ascii=False)}: {_render_json(item, level + 1)}"
                for key, item in value.items()]
        return "{\n" + ",\n".join(rows) + "\n" + pad + "}"
    if isinstance(value, list):
        if not value:
            return "[]"
        compact = json.dumps(value, ensure_ascii=False)
        scalars = all(isinstance(item, (str, int, float, bool, type(None))) for item in value)
        if scalars and len(value) <= 2 and len(compact) <= 80:
            return compact
        rows = [pad + "  " + _render_json(item, level + 1) for item in value]
        return "[\n" + ",\n".join(rows) + "\n" + pad + "]"
    return json.dumps(value, ensure_ascii=False)


def union_json(root, name):
    """Print an additive JSON merge from immutable index stages; never write."""
    if not str(name).endswith(".json"):
        raise ValueError("json union requires a .json path")
    try:
        parsed = [json.loads(blob) for blob in _unmerged_texts(root, name, "json union")]
    except json.JSONDecodeError as exc:
        raise ValueError("json union requires valid JSON parents") from exc
    return _render_json(_union_value(*parsed)) + "\n"
