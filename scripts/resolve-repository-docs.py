#!/usr/bin/env python3
"""Regenerate merged or staged documentation using the existing pinned generator."""
import argparse
import json
import subprocess
from pathlib import Path

import repository_docs


def changed(root, *options):
    return set(subprocess.run(
        ["git", "diff", "--name-only", "--relative", "-z", *options],
        cwd=root, check=True, capture_output=True,
    ).stdout.decode().split("\0")) - {""}


def resolve(root, staged=False):
    root = Path(root).resolve()
    registry = repository_docs.local(root, "repository-docs.json")
    data = subprocess.run(
        ["git", "show", ":repository-docs.json"], cwd=root, check=True, capture_output=True,
    ).stdout if staged else registry.read_bytes()
    config = json.loads(data)
    output = repository_docs.local(root, config["output"]).relative_to(root).as_posix()
    unresolved = sorted(changed(root, "--diff-filter=U") - {output})
    if unresolved:
        raise ValueError("resolve source conflicts first: " + ", ".join(unresolved))
    if staged:
        inputs = {"repository-docs.json", output, *config["entrypoints"]}
        inputs.update(item["path"] for item in config["sources"])
        inputs.update(item["destination"] for item in config["imports"])
        inputs |= {repository_docs.local(root, name).relative_to(root).as_posix() for name in inputs}
        dirty = changed(root) & inputs
        if not changed(root, "--cached") & inputs and dirty:
            return
        # Never stage documentation derived from bytes absent from this commit.
        tracked = set(subprocess.run(
            ["git", "ls-files", "--cached", "-z"], cwd=root, check=True, capture_output=True,
        ).stdout.decode().split("\0"))
        unstaged = sorted(dirty | (inputs - {output} - tracked))
        if unstaged:
            raise ValueError("stage or stash documentation inputs first: " + ", ".join(unstaged))
    errors = repository_docs.run(root, write=True)
    if errors:
        raise ValueError("; ".join(errors))
    subprocess.run(["git", "add", "--", output], cwd=root, check=True)
    print("repository-docs: regenerated and staged " + output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".")
    parser.add_argument("--staged", action="store_true", help="refresh the commit projection; preserve unstaged documentation inputs")
    args = parser.parse_args()
    try:
        resolve(args.root, args.staged)
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as exc:
        parser.exit(1, "repository-docs: " + str(exc) + "\n")


if __name__ == "__main__":
    main()
