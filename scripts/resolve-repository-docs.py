#!/usr/bin/env python3
"""Refresh generated documentation from merged or staged sources with the pinned generator."""
import argparse
import json
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


def resolve(root, refresh_lockfile=False):
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
    if refresh_lockfile:
        dirty = subprocess.run(
            ["git", "diff", "--name-only", "--", "package.json", "**/package.json",
             "pnpm-workspace.yaml", "pnpm-lock.yaml", ".npmrc", output],
            cwd=root, check=True, capture_output=True, text=True,
        ).stdout.strip()
        if dirty:
            raise ValueError("unstaged dependency edits: " + dirty.replace("\n", ", "))
        # Refuse pinned-source drift before invoking the dependency resolver.
        errors = repository_docs.run(root)
        if errors and errors != ["source projection stale: " + output]:
            raise ValueError("; ".join(errors))
        # Explicit repair only: normal commit hooks and CI retain frozen installs.
        lockfile = repository_docs.local(root, "pnpm-lock.yaml")
        previous_lockfile = lockfile.read_bytes() if lockfile.exists() else None
        try:
            for mode in (["--no-frozen-lockfile"], ["--frozen-lockfile", "--offline"]):
                subprocess.run(
                    ["corepack", "pnpm", "install", "--lockfile-only", "--ignore-scripts", *mode],
                    cwd=root, check=True,
                )
        except (OSError, subprocess.CalledProcessError):
            # Failed repairs must remain retryable without discarding local edits.
            if previous_lockfile is None:
                lockfile.unlink(missing_ok=True)
            else:
                lockfile.write_bytes(previous_lockfile)
            raise
    errors = repository_docs.run(root, write=True)
    if errors:
        raise ValueError("; ".join(errors))
    outputs = [output, "pnpm-lock.yaml"] if refresh_lockfile else [output]
    subprocess.run(["git", "add", "--", *outputs], cwd=root, check=True)
    print("repository-docs: regenerated and staged " + output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--staged", action="store_true", help="refresh from the Git index before commit")
    mode.add_argument("--refresh-lockfile", action="store_true", help="repair and verify the pnpm lockfile before refreshing docs")
    args = parser.parse_args()
    try:
        if args.staged:
            resolve_staged(args.root)
        else:
            resolve(args.root, args.refresh_lockfile)
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as exc:
        parser.exit(1, "repository-docs: " + str(exc) + "\n")


if __name__ == "__main__":
    main()
