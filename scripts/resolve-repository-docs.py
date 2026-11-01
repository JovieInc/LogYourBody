#!/usr/bin/env python3
"""Refresh generated documentation from merged or staged sources with the pinned generator."""
import argparse
import difflib
import json
import re
import subprocess
import tempfile
from contextlib import ExitStack, contextmanager
from pathlib import Path

import repository_docs


@contextmanager
def restore_dependency_artifacts_on_failure(root, output):
    paths = [repository_docs.local(root, name) for name in ("pnpm-lock.yaml", output)]
    originals = {path: path.read_bytes() if path.exists() else None for path in paths}
    try:
        yield
    except (ValueError, OSError, subprocess.CalledProcessError):
        # Failed dependency repairs restore both artifacts, including staging failures.
        for path, original in originals.items():
            if original is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(original)
        raise


def staged_bytes(root, name):
    return subprocess.run(
        ["git", "show", ":" + name], cwd=root, check=True, capture_output=True,
    ).stdout


def merge_sections(root, name):
    """Propose an additive documentation merge from immutable index stages; never write."""
    root = Path(root).resolve()
    repository_docs.local(root, name)
    if not name.startswith("docs/") or not name.endswith(".md"):
        raise ValueError("section merging requires a docs/*.md path")

    def git(*args):
        return subprocess.run(
            ["git", *args], cwd=root, check=True, capture_output=True, text=True,
        ).stdout

    git("rev-parse", "--verify", "MERGE_HEAD")
    entries = git("ls-files", "--unmerged", "-z", "--", name).strip("\0").split("\0")
    stages = [entry.split("\t", 1)[0].split() for entry in entries]
    if len(stages) != 3 or {row[2] for row in stages if len(row) == 3} != {"1", "2", "3"}:
        raise ValueError("section merging requires all three unmerged stages")
    if any(row[0] not in {"100644", "100755"} for row in stages):
        raise ValueError("section merging requires regular indexed files")
    base, ours, theirs = [git("show", f":{stage}:{name}") for stage in (1, 2, 3)]
    for source in (base, ours, theirs):
        if re.search(r"(?m)^(?:<{2,}|\|{2,}|={2,}|>{2,})(?: |\r?$)", source):
            raise ValueError("section merging refuses conflict markers in a parent")
    headings = lambda source: [
        " ".join(title.split()).casefold()
        for title in re.findall(r"(?m)^#{1,6} +(.+?) *#*\s*$", source)
    ]
    known = set(headings(base) + headings(ours))
    original, incoming = base.splitlines(keepends=True), theirs.splitlines(keepends=True)
    additions = []
    for tag, start, _, first, last in difflib.SequenceMatcher(
        None, original, incoming, autojunk=False,
    ).get_opcodes():
        if tag == "equal":
            continue
        if tag != "insert":
            raise ValueError("incoming documentation must only add standalone sections")
        block = "".join(incoming[first:last]).strip("\n")
        prefix = "".join(original[:start])
        if (not block.startswith("## ") or re.search(r"(?m)^# ", block)
                or len(re.findall(r"(?m)^(?:`{3,}|~{3,})", prefix)) % 2):
            raise ValueError("incoming additions must start with a standalone level-two section")
        for title in headings(block):
            if title in known:
                raise ValueError("incoming section heading already exists: " + title)
            known.add(title)
        additions.append(block)
    if not additions:
        raise ValueError("no incoming sections to merge")
    return ours.rstrip("\n") + "\n\n" + "\n\n".join(additions) + "\n"


def union_manifests(root):
    """Additive manifest union keeps every parent test input."""
    from manifest_union import apply_manifest_union
    apply_manifest_union(root)


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
    # Rebuild a conflicted projection from staged inputs before resolving unrelated ledgers.
    # Every actual input must have stage zero; staged_bytes fails closed otherwise.
    # An unrelated ledger conflict must not deadlock the two existing merge resolvers.
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
    original = output.read_bytes() if output.exists() else None
    try:
        output.write_bytes(projection)
        subprocess.run(["git", "add", "--", config["output"]], cwd=root, check=True)
    except (OSError, subprocess.CalledProcessError):
        # Keep failed staging retryable, including the original conflict markers.
        if original is None:
            output.unlink(missing_ok=True)
        else:
            output.write_bytes(original)
        raise
    print("repository-docs: regenerated and staged " + config["output"] + " from index")


def reviewed_project_pin(root, expected):
    project = "apps/ios/LogYourBody.xcodeproj/project.pbxproj"
    workflow = ".github/workflows/ios-ui-diagnostics.yml"
    if not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise ValueError("reviewed project SHA-256 must be 64 lowercase hex characters")
    snapshots = {}
    for name in (project, workflow):
        path = root / name
        if any(parent.is_symlink() for parent in (path, *path.parents) if parent != root.parent):
            raise ValueError("reviewed project repair refuses symlinks: " + name)
        snapshots[name] = repository_docs.local(root, name).read_bytes()
        if staged_bytes(root, name) != snapshots[name]:
            raise ValueError("stage reviewed project and workflow edits first: " + name)
        # Git supports short markers; raw snapshots can also retain CRLF endings.
        if re.search(rb"(?m)^(?:<{2,}|\|{2,}|={2,}|>{2,})(?: |\r?$)", snapshots[name]):
            raise ValueError("resolve staged conflict markers first: " + name)
    if repository_docs.digest(snapshots[project]) != expected:
        raise ValueError("reviewed project SHA-256 does not match merged source")
    source = snapshots[workflow].decode()
    pattern = r"(?m)^( +'" + re.escape(project) + r"': ')[0-9a-f]{64}(',)$"
    updated, count = re.subn(pattern, lambda match: match[1] + expected + match[2], source)
    if count != 1:
        raise ValueError("expected exactly one diagnostic project pin")
    # Only an explicit reviewed digest may update this trust boundary; never derive it here.
    return workflow, updated


def projection_is_unmerged(root, output):
    result = subprocess.run(
        ["git", "ls-files", "--unmerged", "--", output],
        cwd=root, check=True, capture_output=True, text=True,
    )
    return bool(result.stdout.strip())


def resolve(root, refresh_lockfile=False, verify_lockfile=False, reviewed_project_sha256=None):
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
    # A conflicted source map is rebuilt from the merged index.
    # Unstaged worktree bytes and either parent's projection cannot change fingerprints.
    # The worktree registry still fails closed: import and path errors are not a stale map.
    if (
        not refresh_lockfile
        and not verify_lockfile
        and reviewed_project_sha256 is None
        and projection_is_unmerged(root, output)
    ):
        errors = repository_docs.run(root)
        if errors and errors != ["source projection stale: " + output]:
            raise ValueError("; ".join(errors))
        resolve_staged(root)
        return
    pin_update = None
    if reviewed_project_sha256 is not None:
        pin_update = reviewed_project_pin(root, reviewed_project_sha256)
        # Validate immutable imports before changing either derived artifact.
        errors = repository_docs.run(root)
        if errors and errors != ["source projection stale: " + output]:
            raise ValueError("; ".join(errors))
    with ExitStack() as rollback:
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
            rollback.enter_context(restore_dependency_artifacts_on_failure(root, output))
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
        if pin_update:
            repository_docs.local(root, pin_update[0]).write_text(pin_update[1])
        errors = repository_docs.run(root, write=True)
        if errors:
            raise ValueError("; ".join(errors))
        outputs = [output, "pnpm-lock.yaml"] if refresh_lockfile else [output]
        if pin_update:
            outputs.append(pin_update[0])
        subprocess.run(["git", "add", "--", *outputs], cwd=root, check=True)
        print("repository-docs: regenerated and staged " + output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--staged", action="store_true", help="refresh from the Git index before commit")
    mode.add_argument("--refresh-lockfile", action="store_true", help="repair and verify the pnpm lockfile before refreshing docs")
    mode.add_argument("--verify-lockfile", action="store_true", help="verify the frozen pnpm lockfile offline before refreshing docs")
    mode.add_argument("--reviewed-project-sha256", help="refresh the diagnostic project pin using an explicitly reviewed merged-project digest")
    mode.add_argument("--merge-sections", metavar="PATH", help="print a proposed docs merge retaining the branch plus new incoming sections; review and stage explicitly")
    mode.add_argument("--union-manifests", action="store_true", help="keep every parent shared-lib test input and turbo string, then regenerate the source projection")
    args = parser.parse_args()
    try:
        if args.merge_sections:
            print(merge_sections(args.root, args.merge_sections), end="")
        elif args.union_manifests:
            union_manifests(args.root)
            resolve(args.root)
        elif args.staged:
            resolve_staged(args.root)
        else:
            resolve(args.root, args.refresh_lockfile, args.verify_lockfile, args.reviewed_project_sha256)
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as exc:
        parser.exit(1, "repository-docs: " + str(exc) + "\n")


if __name__ == "__main__":
    main()
