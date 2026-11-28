"""Reconcile package manifests during an explicit dependency refresh."""
import json
import os
import re
import stat
import subprocess
import tempfile
from contextlib import contextmanager, nullcontext
from pathlib import Path

import repository_docs
from json_union import _render_json, _unmerged_texts
from manifest_union import parse_json_spans

_MISSING = object()
_CONFLICT = object()
_DEPENDENCIES = {"dependencies", "devDependencies", "optionalDependencies", "peerDependencies"}
_STABLE = re.compile(r"([~^])(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)")


def _git(root, *args, data=None, env=None):
    return subprocess.run(
        ["git", *args], cwd=root, check=True, capture_output=True, input=data, env=env,
    ).stdout


def _unique_object(pairs):
    result = dict(pairs)
    if len(result) != len(pairs):
        raise ValueError("dependency manifest union refuses duplicate JSON keys")
    return result


def _prefer_changed(base, ours, theirs):
    if ours == theirs or theirs == base:
        return ours
    if ours == base:
        return theirs
    return _CONFLICT


def _stable_range(specifier):
    match = _STABLE.fullmatch(specifier) if isinstance(specifier, str) else None
    if not match:
        return None
    operator, *parts = match.groups()
    return operator, tuple(int(part) for part in parts)


def _range_ceiling(operator, version):
    major, minor, patch = version
    if operator == "~" or (major == 0 and minor > 0):
        return major, minor + 1, 0
    if major == 0:
        return 0, 0, patch + 1
    return major + 1, 0, 0


def _merge_range(base, ours, theirs, name):
    left, right = _stable_range(ours), _stable_range(theirs)
    if left and right and left[0] == right[0]:
        operator, first_version = left
        second_version = right[1]
        baseline = _stable_range(base)
        forward = base is _MISSING or (
            baseline and baseline[0] == operator and baseline[1] < min(first_version, second_version)
        )
        if forward and _range_ceiling(operator, first_version) == _range_ceiling(operator, second_version):
            return ours if first_version > second_version else theirs
    raise ValueError("dependency manifest union incompatible " + name)


def _dependency_map(value, field):
    if value is _MISSING:
        return {}
    if not isinstance(value, dict) or any(not isinstance(spec, str) for spec in value.values()):
        raise ValueError("dependency manifest union expected string specifiers in " + field)
    return value


def _merge_dependencies(base, ours, theirs, field):
    prior, left, right = (_dependency_map(value, field) for value in (base, ours, theirs))
    result = _prefer_changed(base, ours, theirs)
    if result is not _CONFLICT:
        return result
    if ours is _MISSING or theirs is _MISSING:
        raise ValueError("dependency manifest union incompatible " + field)
    result = {}
    for name in sorted(left.keys() | right.keys() | prior.keys()):
        old, first, second = (group.get(name, _MISSING) for group in (prior, left, right))
        chosen = _prefer_changed(old, first, second)
        if chosen is _CONFLICT:
            chosen = _merge_range(old, first, second, field + "." + name)
        if chosen is not _MISSING:
            result[name] = chosen
    return result


def _merged_package(base, ours, theirs):
    if not all(isinstance(value, dict) for value in (base, ours, theirs)):
        raise ValueError("dependency manifest union expected package.json objects")
    merged = {}
    for name in dict.fromkeys((*ours, *theirs, *base)):
        old, left, right = (package.get(name, _MISSING) for package in (base, ours, theirs))
        chosen = (_merge_dependencies(old, left, right, name) if name in _DEPENDENCIES
                  else _prefer_changed(old, left, right))
        if chosen is _CONFLICT:
            raise ValueError("dependency manifest union incompatible " + name)
        if chosen is not _MISSING:
            merged[name] = chosen
    return merged


def _render_package(source, ours, merged):
    if list(ours) != list(merged):
        return (_render_json(merged) + "\n").encode()
    for name, node in reversed(parse_json_spans(source)[1]):
        if ours[name] != merged[name]:
            source = source[:node[2]] + _render_json(merged[name], 1) + source[node[3]:]
    return source.encode()


def _snapshot(path):
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode):
        raise ValueError("dependency manifest union requires a regular worktree file: " + str(path))
    return (info.st_dev, info.st_ino, info.st_mode), path.read_bytes()


def _write_if_unchanged(path, expected, rendered):
    with tempfile.TemporaryDirectory(dir=path.parent, prefix=".dependency-manifest-") as directory:
        copy = Path(directory) / path.name
        copy.write_bytes(rendered)
        os.chmod(copy, stat.S_IMODE(expected[0][2]))
        written = _snapshot(copy)
        if _snapshot(path) != expected:
            raise ValueError("dependency manifest union inputs changed; review and retry")
        os.replace(copy, path)
        return written


def _plan(root, name):
    path = root / name
    if repository_docs.local(root, name) != path:
        raise ValueError("dependency manifest union refuses a symlink: " + name)
    original = _snapshot(path)
    if _git(root, "show", "AUTO_MERGE:" + name) != original[1]:
        raise ValueError("dependency manifest union refuses worktree edits: " + name)
    texts = _unmerged_texts(root, name, "dependency manifest union")
    base, ours, theirs = (json.loads(text, object_pairs_hook=_unique_object) for text in texts)
    merged = _merged_package(base, ours, theirs)
    return path, original, _render_package(texts[1], ours, merged)


def _owns_lock(lock, original):
    try:
        return os.path.samestat(lock.lstat(), original)
    except FileNotFoundError:
        return False


def _edit_index(root, index_args, expected, edit, verify):
    """Compare and replace the relevant stages under Git's index lock."""
    index = Path(_git(root, "rev-parse", "--path-format=absolute", "--git-path", "index").decode().strip())
    lock = index.with_name(index.name + ".lock")
    output = lock.open("xb")
    owner = os.fstat(output.fileno())
    try:
        with output, tempfile.NamedTemporaryFile(dir=index.parent, prefix="index.manifest-", delete=False) as file:
            alternate = Path(file.name)
            try:
                if _git(root, *index_args) != expected:
                    raise ValueError("dependency manifest union index changed; review and retry")
                file.write(index.read_bytes())
                file.close()
                env = {**os.environ, "GIT_INDEX_FILE": str(alternate)}
                edit(env)
                updated = _git(root, *index_args, env=env)
                verify(env, updated)
                output.write(alternate.read_bytes())
                os.chmod(lock, stat.S_IMODE(index.lstat().st_mode))
            finally:
                alternate.unlink(missing_ok=True)
        if not _owns_lock(lock, owner):
            raise ValueError("dependency manifest union lost the index lock; review and retry")
        os.replace(lock, index)
        return updated
    finally:
        if _owns_lock(lock, owner):
            lock.unlink()


@contextmanager
def _stage_conflicts(root, names):
    _git(root, "rev-parse", "--verify", "MERGE_HEAD")
    index_args = ("ls-files", "--stage", "-z", "--", *names)
    original_index = _git(root, *index_args)
    plan = [_plan(root, name) for name in names]

    def add(env):
        _git(root, "add", "--", *names, env=env)

    def verify_add(env, _updated):
        if any(_git(root, "show", ":" + name, env=env) != rendered
               for name, (_, _, rendered) in zip(names, plan)):
            raise ValueError("dependency manifest union worktree changed; review and retry")

    def restore(env):
        object_width = len(original_index.split(b" ", 2)[1])
        remove = b"".join(b"0 " + b"0" * object_width + b"\t" + name.encode() + b"\0" for name in names)
        _git(root, "update-index", "-z", "--index-info", data=remove + original_index, env=env)

    def verify_restore(_env, restored):
        if restored != original_index:
            raise ValueError("dependency manifest union could not restore the original stages")

    written = []
    staged = None
    try:
        for path, original, rendered in plan:
            written.append((path, original, _write_if_unchanged(path, original, rendered)))
        staged = _edit_index(root, index_args, original_index, add, verify_add)
        yield
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        if any(_snapshot(path) != state for path, _, state in written):
            raise ValueError("dependency manifest union changed during repair; review and retry") from error
        try:
            if staged is not None:
                _edit_index(root, index_args, staged, restore, verify_restore)
        finally:
            for path, (_, original), state in written:
                _write_if_unchanged(path, state, original)
        raise

def prepare_dependency_manifest_merge(root, unresolved, refresh):
    """Stage only pure package manifest conflicts, restoring them if repair fails."""
    if not unresolved:
        return nullcontext()
    if not refresh or any(Path(name).name != "package.json" for name in unresolved):
        raise ValueError("resolve source conflicts first: " + ", ".join(unresolved))
    return _stage_conflicts(root, unresolved)
