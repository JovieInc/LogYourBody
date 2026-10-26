#!/usr/bin/env python3
"""Resolve generated documentation conflicts using the existing pinned generator."""
import argparse
import json
import subprocess
from pathlib import Path

import repository_docs


def git_paths(root, *args):
    return set(subprocess.run(
        ["git", *args, "-z"], cwd=root, check=True, capture_output=True,
    ).stdout.decode().split("\0")) - {""}


def resolve(root, if_staged=False):
    root = Path(root).resolve()
    if if_staged:
        registry = subprocess.run(
            ["git", "show", ":repository-docs.json"], cwd=root, check=True, capture_output=True,
        ).stdout
    else:
        registry = repository_docs.local(root, "repository-docs.json").read_text()
    config = json.loads(registry)
    output = repository_docs.local(root, config["output"]).relative_to(root).as_posix()
    conflicts = git_paths(root, "diff", "--name-only", "--diff-filter=U", "--relative")
    unresolved = sorted(conflicts - {output})
    if unresolved:
        raise ValueError("resolve source conflicts first: " + ", ".join(unresolved))
    if if_staged:
        inputs = {"repository-docs.json"}
        inputs.update(item["path"] for item in config["sources"])
        inputs.update(item["destination"] for item in config["imports"])
        inputs = {repository_docs.local(root, name).relative_to(root).as_posix() for name in inputs}
        watched = inputs | {output}
        if not watched & git_paths(root, "diff", "--cached", "--name-only", "--relative"):
            return
        # The generated document must describe the commit, never unstaged edits.
        dirty = watched & git_paths(root, "diff", "--name-only", "--relative")
        missing = inputs - git_paths(root, "ls-files", "--cached")
        if dirty or missing:
            raise ValueError("stage or restore projection inputs first: " + ", ".join(sorted(dirty | missing)))
    errors = repository_docs.run(root, write=True)
    if errors:
        raise ValueError("; ".join(errors))
    subprocess.run(["git", "add", "--", output], cwd=root, check=True)
    print("repository-docs: regenerated and staged " + output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".")
    parser.add_argument("--if-staged", action="store_true", help="refresh only staged projection inputs; refuse unstaged input edits")
    args = parser.parse_args()
    try:
        resolve(args.root, args.if_staged)
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as exc:
        parser.exit(1, "repository-docs: " + str(exc) + "\n")


if __name__ == "__main__":
    main()
