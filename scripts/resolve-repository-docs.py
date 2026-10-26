#!/usr/bin/env python3
"""Repair generated documentation from merged or staged sources with the pinned generator."""
import argparse
import json
import subprocess
from pathlib import Path
from tempfile import TemporaryDirectory

import repository_docs


def resolve_staged(root):
    root = Path(root).resolve()

    def git(*args):
        return subprocess.run(["git", *args], cwd=root, check=True, capture_output=True).stdout

    if git("diff", "--name-only", "--diff-filter=U", "-z"):
        raise ValueError("resolve source conflicts first before staged projection repair")
    entries = {}
    for row in git("ls-files", "--stage", "-z").split(b"\0"):
        if row:
            metadata, name = row.split(b"\t", 1)
            entries[name.decode()] = metadata.split()

    def read_index(name):
        mode, oid, stage = entries.get(name, (None, None, None))
        if mode not in (b"100644", b"100755") or stage != b"0":
            raise ValueError("regular staged file required: " + name)
        return git("cat-file", "blob", oid.decode())

    # Render the index in isolation so partial source edits never enter the projection.
    with TemporaryDirectory(prefix="repository-docs-index-") as directory:
        snapshot = Path(directory)
        registry = "repository-docs.json"
        data = read_index(registry)
        config = json.loads(data)
        (snapshot / registry).write_bytes(data)
        inputs = set(config["entrypoints"])
        inputs.update(item["path"] for item in config["sources"])
        inputs.update(item["destination"] for item in config["imports"])
        for name in sorted(inputs):
            target = repository_docs.local(snapshot, name)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(read_index(name))
        errors = repository_docs.run(snapshot, write=True)
        if errors:
            raise ValueError("; ".join(errors))
        output = config["output"]
        projection = repository_docs.local(snapshot, output).read_bytes()

    previous = read_index(output) if output in entries else None
    if previous == projection:
        return
    target = repository_docs.local(root, output)
    if target != root / output:
        raise ValueError("projection path traverses a symlink")
    if target.exists() and target.read_bytes() not in (previous, projection):
        raise ValueError("unstaged projection edits; save them before regenerating: " + output)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(projection)
    git("add", "--", output)
    print("repository-docs: regenerated and staged " + output + " from the index")


def resolve(root):
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
    errors = repository_docs.run(root, write=True)
    if errors:
        raise ValueError("; ".join(errors))
    subprocess.run(["git", "add", "--", output], cwd=root, check=True)
    print("repository-docs: regenerated and staged " + output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".")
    parser.add_argument("--staged", action="store_true", help="regenerate only from staged inputs")
    args = parser.parse_args()
    try:
        (resolve_staged if args.staged else resolve)(args.root)
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as exc:
        parser.exit(1, "repository-docs: " + str(exc) + "\n")


if __name__ == "__main__":
    main()
