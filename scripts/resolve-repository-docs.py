#!/usr/bin/env python3
"""Regenerate documentation after merges or staged source updates."""
import argparse
import json
import subprocess
import tempfile
from pathlib import Path

import repository_docs


def git(root, *args):
    return subprocess.run(["git", *args], cwd=root, check=True, capture_output=True).stdout


def refresh_staged(root, config):
    # Generate from the index so partially staged sources never leak into a commit.
    registry = "repository-docs.json"
    inputs = {registry, *config["entrypoints"],
              *(item["path"] for item in config["sources"]),
              *(item["destination"] for item in config["imports"])}
    changed = set(git(root, "diff", "--cached", "--name-only", "-z").decode().split("\0"))
    if not changed.intersection(inputs | {config["output"]}):
        return
    output = repository_docs.local(root, config["output"])
    if output != root / config["output"]:
        raise ValueError("symlinked projection output: " + config["output"])
    with tempfile.TemporaryDirectory(prefix="repository-docs-index-") as directory:
        snapshot = Path(directory)
        for name in sorted(inputs):
            target = repository_docs.local(snapshot, name)
            mode = git(root, "ls-files", "--stage", "-z", "--", name).split(b" ", 1)[0]
            if mode not in (b"100644", b"100755"):
                raise ValueError("projection input must be a staged regular file: " + name)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(git(root, "show", ":" + name))
        errors = repository_docs.run(snapshot, write=True)
        if errors:
            raise ValueError("; ".join(errors))
        projection = repository_docs.local(snapshot, config["output"]).read_bytes()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(projection)
    git(root, "add", "--", config["output"])
    print("repository-docs: regenerated and staged " + config["output"])


def resolve(root, staged=False):
    root = Path(root).resolve()
    config = json.loads(git(root, "show", ":repository-docs.json") if staged else
                        repository_docs.local(root, "repository-docs.json").read_text())
    output = repository_docs.local(root, config["output"]).relative_to(root).as_posix()
    conflicts = subprocess.run(
        ["git", "diff", "--name-only", "--diff-filter=U", "--relative", "-z"],
        cwd=root, check=True, capture_output=True,
    ).stdout.decode().split("\0")
    unresolved = sorted(set(conflicts) - {"", output})
    if unresolved:
        raise ValueError("resolve source conflicts first: " + ", ".join(unresolved))
    if staged:
        refresh_staged(root, config)
        return
    errors = repository_docs.run(root, write=True)
    if errors:
        raise ValueError("; ".join(errors))
    subprocess.run(["git", "add", "--", output], cwd=root, check=True)
    print("repository-docs: regenerated and staged " + output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".")
    parser.add_argument("--staged", action="store_true", help="refresh from staged inputs only when they change")
    args = parser.parse_args()
    try:
        resolve(args.root, args.staged)
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as exc:
        parser.exit(1, "repository-docs: " + str(exc) + "\n")


if __name__ == "__main__":
    main()
