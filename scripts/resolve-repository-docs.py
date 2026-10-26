#!/usr/bin/env python3
"""Refresh generated documentation for merges or staged source changes."""
import argparse
import json
import subprocess
from pathlib import Path

import repository_docs


def refresh_staged(root):
    root = Path(root).resolve()
    changed = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--no-renames", "--relative", "-z"],
        cwd=root, check=True, capture_output=True,
    ).stdout.decode().split("\0")
    if not any(changed):
        return
    registry = "repository-docs.json"
    config = json.loads(subprocess.run(
        ["git", "show", ":" + registry], cwd=root, check=True, capture_output=True,
    ).stdout)
    inputs = {registry, *config["entrypoints"],
              *(item["path"] for item in config["sources"]),
              *(item["destination"] for item in config["imports"])}
    output = config["output"]
    if not set(changed) & (inputs | {output}):
        return
    # Generate only from fully staged inputs; never fold local edits into a commit.
    for name in sorted(inputs | {output}):
        path = repository_docs.local(root, name)
        indexed = subprocess.run(
            ["git", "show", ":" + name], cwd=root, capture_output=True,
        )
        if name == output and not path.exists() and indexed.returncode:
            continue
        if indexed.returncode or not path.is_file() or path.read_bytes() != indexed.stdout:
            raise ValueError("stage or restore documentation input before refreshing: " + name)
    resolve(root)


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
    parser.add_argument("--staged", action="store_true",
                        help="refresh only when a documentation input is staged; refuse unstaged input edits")
    args = parser.parse_args()
    try:
        if args.staged:
            refresh_staged(args.root)
        else:
            resolve(args.root)
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as exc:
        parser.exit(1, "repository-docs: " + str(exc) + "\n")


if __name__ == "__main__":
    main()
