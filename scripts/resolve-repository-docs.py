#!/usr/bin/env python3
"""Resolve generated documentation conflicts using the existing pinned generator."""
import argparse
import json
import subprocess
import tempfile
from pathlib import Path

import repository_docs


def resolve(root, staged=False):
    root = Path(root).resolve()
    if staged:
        config = json.loads(subprocess.run(
            ["git", "show", ":repository-docs.json"], cwd=root,
            check=True, capture_output=True,
        ).stdout)
    else:
        config = json.loads(repository_docs.local(root, "repository-docs.json").read_text())
    output = repository_docs.local(root, config["output"]).relative_to(root).as_posix()
    conflicts = subprocess.run(
        ["git", "diff", "--name-only", "--diff-filter=U", "--relative", "-z"],
        cwd=root, check=True, capture_output=True,
    ).stdout.decode().split("\0")
    unresolved = sorted(set(conflicts) - ({""} if staged else {"", output}))
    if unresolved:
        raise ValueError("resolve source conflicts first: " + ", ".join(unresolved))
    if staged:
        # Never overwrite local projection edits or include unstaged source changes.
        dirty = subprocess.run(["git", "diff", "--quiet", "--", output], cwd=root)
        tracked = subprocess.run(
            ["git", "ls-files", "--error-unmatch", "--", output], cwd=root, capture_output=True,
        )
        if dirty.returncode or (tracked.returncode and repository_docs.local(root, output).exists()):
            raise ValueError("projection has unstaged edits: " + output)
        with tempfile.TemporaryDirectory(prefix="repository-docs-index-") as directory:
            snapshot = Path(directory)
            names = {"repository-docs.json", *config["entrypoints"]}
            names.update(item["path"] for item in config["sources"])
            names.update(item["destination"] for item in config["imports"])
            for name in names:
                repository_docs.local(snapshot, name)
            subprocess.run(
                ["git", "checkout-index", "--prefix=" + str(snapshot) + "/", "-z", "--stdin"],
                cwd=root, input="\0".join(sorted(names)) + "\0", text=True,
                check=True, capture_output=True,
            )
            errors = repository_docs.run(snapshot, write=True)
            if errors:
                raise ValueError("; ".join(errors))
            projection = repository_docs.local(snapshot, output).read_bytes()
        target = repository_docs.local(root, output)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(projection)
    else:
        errors = repository_docs.run(root, write=True)
        if errors:
            raise ValueError("; ".join(errors))
    subprocess.run(["git", "add", "--", output], cwd=root, check=True)
    print("repository-docs: regenerated and staged " + output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".")
    parser.add_argument("--staged", action="store_true", help="regenerate from the Git index for pre-commit")
    args = parser.parse_args()
    try:
        resolve(args.root, staged=args.staged)
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as exc:
        parser.exit(1, "repository-docs: " + str(exc) + "\n")


if __name__ == "__main__":
    main()
