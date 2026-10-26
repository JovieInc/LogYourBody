#!/usr/bin/env python3
"""Refresh generated documentation using the existing pinned generator."""
import argparse
import json
import subprocess
from pathlib import Path

import repository_docs


def resolve(root, staged=False):
    root = Path(root).resolve()
    def git(*args):
        return subprocess.run(["git", *args], cwd=root, check=True, capture_output=True).stdout

    registry = "repository-docs.json"
    config = json.loads(git("show", ":" + registry) if staged else repository_docs.local(root, registry).read_bytes())
    output = repository_docs.local(root, config["output"]).relative_to(root).as_posix()
    conflicts = subprocess.run(
        ["git", "diff", "--name-only", "--diff-filter=U", "--relative", "-z"],
        cwd=root, check=True, capture_output=True,
    ).stdout.decode().split("\0")
    unresolved = sorted(set(conflicts) - {"", output})
    if unresolved:
        raise ValueError("resolve source conflicts first: " + ", ".join(unresolved))
    if staged:
        inputs = {registry, *config["entrypoints"],
                  *(item["path"] for item in config["sources"]),
                  *(item["destination"] for item in config["imports"])}
        inputs = {repository_docs.local(root, name).relative_to(root).as_posix() for name in inputs}
        watched = inputs | {output}
        changed = set(git("diff", "--cached", "--name-only", "--no-renames", "-z").decode().split("\0"))
        unstaged = set(git("diff", "--name-only", "--no-renames", "-z").decode().split("\0"))
        tracked = set(git("ls-files", "--cached", "-z").decode().split("\0"))
        dirty = sorted((unstaged & watched) | (inputs - tracked))
        if dirty:
            if not changed & watched:
                return
            raise ValueError("stage or restore documentation inputs first: " + ", ".join(dirty))
    errors = repository_docs.run(root, write=True)
    if errors:
        raise ValueError("; ".join(errors))
    subprocess.run(["git", "add", "--", output], cwd=root, check=True)
    print("repository-docs: regenerated and staged " + output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".")
    parser.add_argument("--staged", action="store_true", help="refresh staged source changes; refuse unstaged documentation inputs")
    args = parser.parse_args()
    try:
        resolve(args.root, staged=args.staged)
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as exc:
        parser.exit(1, "repository-docs: " + str(exc) + "\n")


if __name__ == "__main__":
    main()
