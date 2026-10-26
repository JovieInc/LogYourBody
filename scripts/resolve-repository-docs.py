#!/usr/bin/env python3
"""Repair generated source maps; use --sync-lockfile after dependency manifest updates."""
import argparse
import json
import subprocess
from pathlib import Path

import repository_docs


def resolve(root, sync_lockfile=False):
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
    if sync_lockfile:
        # Validate paths and pinned imports before attempting dependency resolution.
        errors = repository_docs.run(root)
        if errors and errors != ["source projection stale: " + config["output"]]:
            raise ValueError("; ".join(errors))
        subprocess.run(
            ["corepack", "pnpm", "install", "--lockfile-only", "--ignore-scripts", "--no-frozen-lockfile"],
            cwd=root, check=True,
        )
    errors = repository_docs.run(root, write=True)
    if errors:
        raise ValueError("; ".join(errors))
    subprocess.run(["git", "add", "--", output], cwd=root, check=True)
    print("repository-docs: regenerated and staged " + output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".")
    parser.add_argument("--sync-lockfile", action="store_true",
                        help="Refresh the workspace lockfile with pinned pnpm before regenerating; leave it unstaged for review.")
    args = parser.parse_args()
    try:
        resolve(args.root, args.sync_lockfile)
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as exc:
        parser.exit(1, "repository-docs: " + str(exc) + "\n")


if __name__ == "__main__":
    main()
