#!/usr/bin/env python3
"""Resolve generated documentation conflicts using the existing pinned generator."""
import argparse
import json
import subprocess
from pathlib import Path

import repository_docs


def changed(root, *args):
    return set(subprocess.run(
        ["git", "diff", "--name-only", "--relative", "-z", *args],
        cwd=root, check=True, capture_output=True,
    ).stdout.decode().split("\0")) - {""}


def resolve(root, staged=False):
    root = Path(root).resolve()
    config = json.loads(repository_docs.local(root, "repository-docs.json").read_text())
    output = repository_docs.local(root, config["output"]).relative_to(root).as_posix()
    if staged:
        inputs = {"repository-docs.json", output}
        inputs.update(item["path"] for item in config["sources"])
        inputs.update(item["destination"] for item in config["imports"])
        if not changed(root, "--cached") & inputs:
            return
        dirty = sorted(changed(root) & inputs)
        if dirty:
            raise ValueError("stage or stash documentation inputs first: " + ", ".join(dirty))
    unresolved = sorted(changed(root, "--diff-filter=U") - {output})
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
    parser.add_argument("--staged", action="store_true",
                        help="refresh staged documentation inputs without including unstaged edits")
    args = parser.parse_args()
    try:
        resolve(args.root, args.staged)
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as exc:
        parser.exit(1, "repository-docs: " + str(exc) + "\n")


if __name__ == "__main__":
    main()
