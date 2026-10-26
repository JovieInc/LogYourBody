#!/usr/bin/env python3
"""Repair generated documentation from merged or staged sources with the pinned generator."""
import argparse
import json
import subprocess
import tempfile
from pathlib import Path

import repository_docs


def resolve_staged(root):
    def git(*args):
        return subprocess.run(
            ["git", "--literal-pathspecs", "-C", str(root), *args],
            check=True, capture_output=True,
        ).stdout

    def read_staged(name, optional=False):
        entry = git("ls-files", "--stage", "-z", "--", name)
        if not entry:
            if optional:
                return None
            raise ValueError("missing staged input: " + name)
        if entry.split(b" ", 1)[0] not in (b"100644", b"100755"):
            raise ValueError("staged input must be a regular file: " + name)
        return git("show", ":" + name)

    if git("diff", "--name-only", "--diff-filter=U", "-z"):
        raise ValueError("resolve source conflicts first")
    # Materialize only declared inputs; unstaged source edits never enter the map.
    with tempfile.TemporaryDirectory(prefix="repository-docs-index-") as temporary:
        snapshot = Path(temporary)

        def copy(name):
            target = repository_docs.local(snapshot, name)
            data = read_staged(name)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            return data

        config = json.loads(copy("repository-docs.json"))
        output = repository_docs.local(root, config["output"])
        if output != root / config["output"]:
            raise ValueError("symlinked projection: " + config["output"])
        original = read_staged(config["output"], optional=True)
        if (output.read_bytes() if output.is_file() else None) != original:
            raise ValueError("unstaged projection edits: " + config["output"])
        for name in sorted(set(config["entrypoints"] + [i["path"] for i in config["sources"]]
                               + [i["destination"] for i in config["imports"]])):
            copy(name)
        errors = repository_docs.run(snapshot, write=True)
        if errors:
            raise ValueError("; ".join(errors))
        projection = repository_docs.local(snapshot, config["output"]).read_bytes()
        if projection != original:
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_bytes(projection)
            git("add", "--", config["output"])
    print("repository-docs: regenerated and staged " + config["output"])


def resolve(root, staged=False):
    root = Path(root).resolve()
    if staged:
        return resolve_staged(root)
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
    parser.add_argument("--staged", action="store_true", help="regenerate from the Git index, preserving unstaged edits")
    args = parser.parse_args()
    try:
        resolve(args.root, args.staged)
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as exc:
        parser.exit(1, "repository-docs: " + str(exc) + "\n")


if __name__ == "__main__":
    main()
