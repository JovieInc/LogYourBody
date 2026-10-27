#!/usr/bin/env python3
"""Refresh generated documentation from merged or staged sources with the pinned generator."""
import argparse
import json
import re
import subprocess
import tempfile
from contextlib import contextmanager
from pathlib import Path

import repository_docs


@contextmanager
def restore_lockfile_on_failure(root):
    lockfile = repository_docs.local(root, "pnpm-lock.yaml")
    original = lockfile.read_bytes() if lockfile.exists() else None
    try:
        yield
    except (OSError, subprocess.CalledProcessError):
        # Failed dependency repairs must be retryable without manual lockfile cleanup.
        if original is None:
            lockfile.unlink(missing_ok=True)
        else:
            lockfile.write_bytes(original)
        raise


def staged_bytes(root, name):
    return subprocess.run(
        ["git", "show", ":" + name], cwd=root, check=True, capture_output=True,
    ).stdout


def resolve_reviewed_project_pin(root, reviewed_sha256):
    """Resolve only a pin conflict after an explicit review of the indexed project."""
    root = Path(root).resolve()
    project = "apps/ios/LogYourBody.xcodeproj/project.pbxproj"
    workflow = ".github/workflows/ios-ui-diagnostics.yml"
    if not re.fullmatch(r"[0-9a-f]{64}", reviewed_sha256):
        raise ValueError("reviewed project SHA-256 must be 64 lowercase hex characters")
    for name in (project, workflow):
        source = root / name
        if source.is_symlink() or source.resolve() != source:
            raise ValueError("refusing symlinked project pin input: " + name)
    project_bytes = staged_bytes(root, project)
    if ((root / project).read_bytes() != project_bytes
            or repository_docs.digest(project_bytes) != reviewed_sha256):
        raise ValueError("reviewed project SHA-256 must match both index and working tree")

    def git(*args):
        return subprocess.run(["git", *args], cwd=root, check=True, capture_output=True).stdout

    # This opt-in never infers approval or changes a gate, audit pin or other dependency.
    git("rev-parse", "--verify", "MERGE_HEAD")
    pattern = re.compile(rb"(?m)^([ \t]*'" + re.escape(project.encode())
                         + rb"': ')([0-9a-f]{64})(',\n)")

    def repin(source):
        matches = list(pattern.finditer(source))
        if len(matches) != 1:
            raise ValueError("expected exactly one diagnostic project pin")
        match = matches[0]
        return (source[:match.start(2)] + reviewed_sha256.encode() + source[match.end(2):],
                match[0])

    target = root / workflow
    original = target.read_bytes()
    if not git("ls-files", "--unmerged", "--", workflow):
        indexed = staged_bytes(root, workflow)
        if original != indexed or repin(indexed)[0] != indexed:
            raise ValueError("staged project pin retry requires the reviewed pin and no unstaged edits")
        print("repository-docs: verified staged reviewed project pin")
        return
    parents = [git("show", f":{stage}:{workflow}") for stage in (1, 2, 3)]
    replacements = [repin(source) for source in parents]
    if len({source for source, _ in replacements}) != 1:
        raise ValueError("resolve non-pin workflow changes manually")
    base, ours, theirs = [line for _, line in replacements]
    conflict = (rb"(?m)^<{7}[^\n]*\n" + re.escape(ours)
                + rb"(?:^\|{7}[^\n]*\n" + re.escape(base) + rb")?"
                + rb"^={7}\n" + re.escape(theirs) + rb"^>{7}[^\n]*\n")
    reviewed_line = repin(ours)[0]
    resolved, count = re.subn(conflict, lambda _: reviewed_line, original)
    if count != 1 or resolved != replacements[0][0]:
        raise ValueError("expected only the project pin conflict; preserve and review other edits")
    target.write_bytes(resolved)
    try:
        git("add", "--", workflow)
    except (OSError, subprocess.CalledProcessError):
        target.write_bytes(original)
        raise
    print("repository-docs: resolved and staged reviewed project pin " + reviewed_sha256)


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
    conflicted = subprocess.run(
        ["git", "ls-files", "--unmerged", "-z", "--", config["output"]],
        cwd=root, check=True, capture_output=True,
    ).stdout
    # Rebuild a conflicted projection only from stage-0 inputs. An unrelated
    # ledger conflict must not deadlock the two existing merge resolvers.
    if (dirty and not conflicted) or (output.exists() and not tracked):
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


def resolve(root, refresh_lockfile=False, verify_lockfile=False):
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
    if refresh_lockfile or verify_lockfile:
        inputs = ["package.json", "**/package.json", "pnpm-workspace.yaml",
                  "pnpm-lock.yaml", ".npmrc", output]
        dirty = subprocess.run(
            ["git", "diff", "--name-only", "--", *inputs],
            cwd=root, check=True, capture_output=True, text=True,
        ).stdout.strip()
        if dirty:
            raise ValueError("unstaged dependency edits: " + dirty.replace("\n", ", "))
        # Local-only manifests must not enter a lockfile destined for CI.
        untracked = subprocess.run(
            ["git", "ls-files", "--others", "--exclude-standard", "-z", "--", *inputs],
            cwd=root, check=True, capture_output=True, text=True,
        ).stdout.strip("\0")
        if untracked:
            raise ValueError("untracked dependency inputs: " + untracked.replace("\0", ", "))
        # Refuse pinned-source drift before invoking the dependency resolver.
        errors = repository_docs.run(root)
        if errors and errors != ["source projection stale: " + output]:
            raise ValueError("; ".join(errors))
        with restore_lockfile_on_failure(root):
            # Verify valid bot lockfiles without re-resolving unrelated dependencies.
            modes = [["--frozen-lockfile", "--offline"]]
            # Explicit repair only: normal commit hooks and CI retain frozen installs.
            if refresh_lockfile:
                probe = subprocess.run(
                    ["corepack", "pnpm", "install", "--lockfile-only", "--ignore-scripts", *modes[0]],
                    cwd=root, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                )
                print(probe.stdout, end="", flush=True)
                # Refresh only a confirmed manifest mismatch; other failures remain blockers.
                if probe.returncode:
                    if "ERR_PNPM_OUTDATED_LOCKFILE" not in probe.stdout:
                        probe.check_returncode()
                    modes.insert(0, ["--no-frozen-lockfile"])
                else:
                    modes = []
            for mode in modes:
                subprocess.run(
                    ["corepack", "pnpm", "install", "--lockfile-only", "--ignore-scripts", *mode],
                    cwd=root, check=True,
                )
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
    mode.add_argument("--verify-lockfile", action="store_true", help="verify the frozen pnpm lockfile offline before refreshing docs")
    mode.add_argument("--reviewed-project-sha256", help="resolve only the diagnostic project pin conflict using an explicitly reviewed indexed project SHA-256")
    args = parser.parse_args()
    try:
        if args.reviewed_project_sha256:
            resolve_reviewed_project_pin(args.root, args.reviewed_project_sha256)
        elif args.staged:
            resolve_staged(args.root)
        else:
            resolve(args.root, args.refresh_lockfile, args.verify_lockfile)
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as exc:
        parser.exit(1, "repository-docs: " + str(exc) + "\n")


if __name__ == "__main__":
    main()
