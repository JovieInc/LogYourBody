#!/usr/bin/env python3
"""Refresh generated documentation from merged or staged sources with the pinned generator."""
import argparse
import difflib
import json
import re
import subprocess
import tempfile
from contextlib import ExitStack, contextmanager
from pathlib import Path

import repository_docs


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


def staged_bytes(root, name):
    return subprocess.run(
        ["git", "show", ":" + name], cwd=root, check=True, capture_output=True,
    ).stdout


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


def merge_sections(root, name):
    """Propose an additive documentation merge from immutable index stages; never write."""
    root = Path(root).resolve()
    repository_docs.local(root, name)
    if not name.startswith("docs/") or not name.endswith(".md"):
        raise ValueError("section merging requires a docs/*.md path")

    base, ours, theirs = _unmerged_texts(root, name, "section merging")
    headings = lambda source: [
        " ".join(title.split()).casefold()
        for title in re.findall(r"(?m)^#{1,6} +(.+?) *#*\s*$", source)
    ]
    known = set(headings(base) + headings(ours))
    original, incoming = base.splitlines(keepends=True), theirs.splitlines(keepends=True)
    additions = []
    for tag, start, _, first, last in difflib.SequenceMatcher(
        None, original, incoming, autojunk=False,
    ).get_opcodes():
        if tag == "equal":
            continue
        if tag != "insert":
            raise ValueError("incoming documentation must only add standalone sections")
        block = "".join(incoming[first:last]).strip("\n")
        prefix = "".join(original[:start])
        if (not block.startswith("## ") or re.search(r"(?m)^# ", block)
                or len(re.findall(r"(?m)^(?:`{3,}|~{3,})", prefix)) % 2):
            raise ValueError("incoming additions must start with a standalone level-two section")
        for title in headings(block):
            if title in known:
                raise ValueError("incoming section heading already exists: " + title)
            known.add(title)
        additions.append(block)
    if not additions:
        raise ValueError("no incoming sections to merge")
    return ours.rstrip("\n") + "\n\n" + "\n\n".join(additions) + "\n"


def resolve_staged(root):
    root = Path(root).resolve()
    registry = staged_bytes(root, "repository-docs.json")
    config = json.loads(registry)
    output = repository_docs.local(root, config["output"])
    dirty = subprocess.run(
        ["git", "diff", "--name-only", "-z", "--", config["output"]],
        cwd=root, check=True, capture_output=True,
    ).stdout
    tracked = subprocess.run(
        ["git", "ls-files", "--error-unmatch", "--", config["output"]],
        cwd=root, capture_output=True,
    ).returncode == 0
    conflicted = subprocess.run(
        ["git", "ls-files", "--unmerged", "-z", "--", config["output"]],
        cwd=root, check=True, capture_output=True,
    ).stdout
    # Rebuild a conflicted projection from staged inputs before resolving unrelated ledgers.
    # Every actual input must have stage zero; staged_bytes fails closed otherwise.
    # An unrelated ledger conflict must not deadlock the two existing merge resolvers.
    if (dirty and not conflicted) or (output.exists() and not tracked):
        raise ValueError("unstaged projection edits: " + config["output"])
    # Render the index, so partially staged manifests cannot leak into the commit.
    with tempfile.TemporaryDirectory(prefix="repository-docs-index-") as directory:
        snapshot = Path(directory)
        (snapshot / "repository-docs.json").write_bytes(registry)
        names = set(config["entrypoints"])
        names.update(item["path"] for item in config["sources"])
        names.update(item["destination"] for item in config["imports"])
        for name in sorted(names):
            target = repository_docs.local(snapshot, name)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(staged_bytes(root, name))
        errors = repository_docs.run(snapshot, write=True)
        if errors:
            raise ValueError("; ".join(errors))
        projection = repository_docs.local(snapshot, config["output"]).read_bytes()
    output.parent.mkdir(parents=True, exist_ok=True)
    original = output.read_bytes() if output.exists() else None
    try:
        output.write_bytes(projection)
        subprocess.run(["git", "add", "--", config["output"]], cwd=root, check=True)
    except (OSError, subprocess.CalledProcessError):
        # Keep failed staging retryable, including the original conflict markers.
        if original is None:
            output.unlink(missing_ok=True)
        else:
            output.write_bytes(original)
        raise
    print("repository-docs: regenerated and staged " + config["output"] + " from index")


def reviewed_project_pin(root, expected):
    project = "apps/ios/LogYourBody.xcodeproj/project.pbxproj"
    workflow = ".github/workflows/ios-ui-diagnostics.yml"
    if not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise ValueError("reviewed project SHA-256 must be 64 lowercase hex characters")
    snapshots = {}
    for name in (project, workflow):
        path = root / name
        if any(parent.is_symlink() for parent in (path, *path.parents) if parent != root.parent):
            raise ValueError("reviewed project repair refuses symlinks: " + name)
        snapshots[name] = repository_docs.local(root, name).read_bytes()
        if staged_bytes(root, name) != snapshots[name]:
            raise ValueError("stage reviewed project and workflow edits first: " + name)
        # Git supports short markers; raw snapshots can also retain CRLF endings.
        if re.search(rb"(?m)^(?:<{2,}|\|{2,}|={2,}|>{2,})(?: |\r?$)", snapshots[name]):
            raise ValueError("resolve staged conflict markers first: " + name)
    if repository_docs.digest(snapshots[project]) != expected:
        raise ValueError("reviewed project SHA-256 does not match merged source")
    source = snapshots[workflow].decode()
    pattern = r"(?m)^( +'" + re.escape(project) + r"': ')[0-9a-f]{64}(',)$"
    updated, count = re.subn(pattern, lambda match: match[1] + expected + match[2], source)
    if count != 1:
        raise ValueError("expected exactly one diagnostic project pin")
    # Only an explicit reviewed digest may update this trust boundary; never derive it here.
    return workflow, updated


def resolve(root, refresh_lockfile=False, verify_lockfile=False, reviewed_project_sha256=None):
    root = Path(root).resolve()
    config = json.loads(repository_docs.local(root, "repository-docs.json").read_text())
    output = repository_docs.local(root, config["output"]).relative_to(root).as_posix()
    conflicts = subprocess.run(
        ["git", "diff", "--name-only", "--diff-filter=U", "--relative", "-z"],
        cwd=root, check=True, capture_output=True,
    ).stdout.decode().split("\0")
    unresolved = sorted(set(conflicts) - {"", output})
    if unresolved:
        raise ValueError("resolve source conflicts first: " + ", ".join(unresolved))
    pin_update = None
    if reviewed_project_sha256 is not None:
        pin_update = reviewed_project_pin(root, reviewed_project_sha256)
        # Validate immutable imports before changing either derived artifact.
        errors = repository_docs.run(root)
        if errors and errors != ["source projection stale: " + output]:
            raise ValueError("; ".join(errors))
    with ExitStack() as rollback:
        if refresh_lockfile or verify_lockfile:
            inputs = ["package.json", "**/package.json", "pnpm-workspace.yaml",
                      "pnpm-lock.yaml", ".npmrc", output]
            dirty = subprocess.run(
                ["git", "diff", "--name-only", "--", *inputs],
                cwd=root, check=True, capture_output=True, text=True,
            ).stdout.strip()
            if dirty:
                raise ValueError("unstaged dependency edits: " + dirty.replace("\n", ", "))
            # Local-only manifests must not enter a lockfile destined for CI.
            untracked = subprocess.run(
                ["git", "ls-files", "--others", "--exclude-standard", "-z", "--", *inputs],
                cwd=root, check=True, capture_output=True, text=True,
            ).stdout.strip("\0")
            if untracked:
                raise ValueError("untracked dependency inputs: " + untracked.replace("\0", ", "))
            # Refuse pinned-source drift before invoking the dependency resolver.
            errors = repository_docs.run(root)
            if errors and errors != ["source projection stale: " + output]:
                raise ValueError("; ".join(errors))
            rollback.enter_context(restore_dependency_artifacts_on_failure(root, output))
            # Verify valid bot lockfiles without re-resolving unrelated dependencies.
            modes = [["--frozen-lockfile", "--offline"]]
            # Explicit repair only: normal commit hooks and CI retain frozen installs.
            if refresh_lockfile:
                probe = subprocess.run(
                    ["corepack", "pnpm", "install", "--lockfile-only", "--ignore-scripts", *modes[0]],
                    cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                )
                print(probe.stdout, end="", flush=True)
                # Refresh only a confirmed manifest mismatch; other failures remain blockers.
                if probe.returncode:
                    if "ERR_PNPM_OUTDATED_LOCKFILE" not in probe.stdout:
                        probe.check_returncode()
                    modes.insert(0, ["--no-frozen-lockfile"])
                else:
                    modes = []
            for mode in modes:
                subprocess.run(
                    ["corepack", "pnpm", "install", "--lockfile-only", "--ignore-scripts", *mode],
                    cwd=root, check=True,
                )
        if pin_update:
            repository_docs.local(root, pin_update[0]).write_text(pin_update[1])
        errors = repository_docs.run(root, write=True)
        if errors:
            raise ValueError("; ".join(errors))
        outputs = [output, "pnpm-lock.yaml"] if refresh_lockfile else [output]
        if pin_update:
            outputs.append(pin_update[0])
        subprocess.run(["git", "add", "--", *outputs], cwd=root, check=True)
        print("repository-docs: regenerated and staged " + output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--staged", action="store_true", help="refresh from the Git index before commit")
    mode.add_argument("--refresh-lockfile", action="store_true", help="repair and verify the pnpm lockfile before refreshing docs")
    mode.add_argument("--verify-lockfile", action="store_true", help="verify the frozen pnpm lockfile offline before refreshing docs")
    mode.add_argument("--reviewed-project-sha256", help="refresh the diagnostic project pin using an explicitly reviewed merged-project digest")
    mode.add_argument("--merge-sections", metavar="PATH", help="print a proposed docs merge retaining the branch plus new incoming sections; review and stage explicitly")
    mode.add_argument("--union-json", metavar="PATH", help="print an additive JSON merge from index stages; review and stage explicitly")
    args = parser.parse_args()
    try:
        if args.merge_sections:
            print(merge_sections(args.root, args.merge_sections), end="")
        elif args.union_json:
            print(union_json(args.root, args.union_json), end="")
        elif args.staged:
            resolve_staged(args.root)
        else:
            resolve(args.root, args.refresh_lockfile, args.verify_lockfile, args.reviewed_project_sha256)
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as exc:
        parser.exit(1, "repository-docs: " + str(exc) + "\n")


if __name__ == "__main__":
    main()
