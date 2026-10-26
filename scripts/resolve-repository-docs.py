#!/usr/bin/env python3
"""Refresh generated documentation from merged or staged sources with the pinned generator."""
import argparse
import json
import re
import subprocess
import tempfile
from pathlib import Path

import repository_docs


def staged_bytes(root, name):
    return subprocess.run(
        ["git", "show", ":" + name], cwd=root, check=True, capture_output=True,
    ).stdout


def resolve_staged(root):
    root = Path(root).resolve()
    registry = staged_bytes(root, "repository-docs.json")
    config = json.loads(registry)
    output = repository_docs.local(root, config["output"])
    dirty = subprocess.run(
        ["git", "diff", "--name-only", "-z", "--", config["output"]],
        cwd=root, check=True, capture_output=True,
    ).stdout
    tracked = subprocess.run(
        ["git", "ls-files", "--error-unmatch", "--", config["output"]],
        cwd=root, capture_output=True,
    ).returncode == 0
    if dirty or (output.exists() and not tracked):
        raise ValueError("unstaged projection edits: " + config["output"])
    # Render the index, so partially staged manifests cannot leak into the commit.
    with tempfile.TemporaryDirectory(prefix="repository-docs-index-") as directory:
        snapshot = Path(directory)
        (snapshot / "repository-docs.json").write_bytes(registry)
        names = set(config["entrypoints"])
        names.update(item["path"] for item in config["sources"])
        names.update(item["destination"] for item in config["imports"])
        for name in sorted(names):
            target = repository_docs.local(snapshot, name)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(staged_bytes(root, name))
        errors = repository_docs.run(snapshot, write=True)
        if errors:
            raise ValueError("; ".join(errors))
        projection = repository_docs.local(snapshot, config["output"]).read_bytes()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(projection)
    subprocess.run(["git", "add", "--", config["output"]], cwd=root, check=True)
    print("repository-docs: regenerated and staged " + config["output"] + " from index")


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
        # Validate pinned sources and output safety before invoking the package manager.
        errors = [error for error in repository_docs.run(root)
                  if error != "source projection stale: " + config["output"]]
        if errors:
            raise ValueError("; ".join(errors))
        manifest = json.loads(repository_docs.local(root, "package.json").read_text())
        pin = re.fullmatch(r"pnpm@(\d+\.\d+\.\d+)(?:\+[^\s]+)?", manifest.get("packageManager", ""))
        if not pin:
            raise ValueError("lockfile repair requires an exact pnpm packageManager pin")
        version = subprocess.run(["pnpm", "--version"], cwd=root, check=True,
                                 capture_output=True, text=True).stdout.strip()
        if version != pin[1]:
            raise ValueError("lockfile repair requires pnpm@" + pin[1] + "; found " + version)
        subprocess.run(["pnpm", "install", "--lockfile-only", "--ignore-scripts",
                        "--no-frozen-lockfile"], cwd=root, check=True)
    errors = repository_docs.run(root, write=True)
    if errors:
        raise ValueError("; ".join(errors))
    subprocess.run(["git", "add", "--", output], cwd=root, check=True)
    print("repository-docs: regenerated and staged " + output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--staged", action="store_true", help="refresh from the Git index before commit")
    mode.add_argument("--sync-lockfile", action="store_true",
                      help="refresh the lockfile with pinned pnpm before regenerating docs")
    args = parser.parse_args()
    try:
        if args.staged:
            resolve_staged(args.root)
        else:
            resolve(args.root, args.sync_lockfile)
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as exc:
        parser.exit(1, "repository-docs: " + str(exc) + "\n")


if __name__ == "__main__":
    main()
