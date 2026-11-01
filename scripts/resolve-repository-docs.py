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


PROJECT_PATH = "apps/ios/LogYourBody.xcodeproj/project.pbxproj"
WORKFLOW_PATH = ".github/workflows/ios-ui-diagnostics.yml"
LEDGER_PATH = "packages/shared-lib/corrections.json"
# Git supports short markers; raw snapshots can also retain CRLF endings.
CONFLICT_MARKER = re.compile(rb"(?m)^(?:<{2,}|\|{2,}|={2,}|>{2,})(?: |\r?$)")


def conflict_names(root):
    raw = subprocess.run(
        ["git", "diff", "--name-only", "--diff-filter=U", "--relative", "-z"],
        cwd=root, check=True, capture_output=True,
    ).stdout.decode().split("\0")
    return sorted({name for name in raw if name})


def unmerged_stages(root, name):
    raw = subprocess.run(
        ["git", "ls-files", "--unmerged", "-z", "--", name],
        cwd=root, check=True, capture_output=True,
    ).stdout.decode().strip("\0")
    if not raw:
        return []
    return [entry.split("\t", 1)[0].split() for entry in raw.split("\0") if entry]


def refuse_reviewed_symlink(root, name):
    path = root / name
    if any(parent.is_symlink() for parent in (path, *path.parents) if parent != root.parent):
        raise ValueError("reviewed project repair refuses symlinks: " + name)


def pin_expression():
    return re.compile(r"(?m)^( +'" + re.escape(PROJECT_PATH) + r"': ')[0-9a-f]{64}(',)$")


def replace_pin(source, expected):
    matches = list(pin_expression().finditer(source))
    if len(matches) != 1:
        raise ValueError("expected exactly one diagnostic project pin")
    match = matches[0]
    return source[:match.start()] + match.group(1) + expected + match.group(2) + source[match.end():]


def show_stage(root, stage, name):
    return subprocess.run(
        ["git", "show", f":{stage}:{name}"], cwd=root, check=True, capture_output=True,
    ).stdout


def reviewed_project_pin(root, expected):
    """Replace a pin-only diagnostic workflow conflict with the explicit reviewed project digest."""
    if not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise ValueError("reviewed project SHA-256 must be 64 lowercase hex characters")
    for name in (PROJECT_PATH, WORKFLOW_PATH):
        refuse_reviewed_symlink(root, name)
    if unmerged_stages(root, PROJECT_PATH):
        raise ValueError("resolve the merged project before refreshing its diagnostic pin")
    project = staged_bytes(root, PROJECT_PATH)
    if repository_docs.local(root, PROJECT_PATH).read_bytes() != project:
        raise ValueError("stage reviewed project and workflow edits first: " + PROJECT_PATH)
    if CONFLICT_MARKER.search(project):
        raise ValueError("resolve staged conflict markers first: " + PROJECT_PATH)
    if repository_docs.digest(project) != expected:
        raise ValueError("reviewed project SHA-256 does not match merged source")
    stages = unmerged_stages(root, WORKFLOW_PATH)
    if stages:
        if len(stages) != 3 or {row[2] for row in stages if len(row) == 3} != {"1", "2", "3"}:
            raise ValueError("diagnostic pin repair requires all three workflow stages")
        if any(row[0] not in {"100644", "100755"} for row in stages):
            raise ValueError("diagnostic pin repair requires a regular workflow file")
        parents = {}
        for stage in ("1", "2", "3"):
            blob = show_stage(root, stage, WORKFLOW_PATH)
            if CONFLICT_MARKER.search(blob):
                raise ValueError("diagnostic pin repair refuses conflict markers in a parent")
            parents[stage] = blob.decode()
            replace_pin(parents[stage], "0" * 64)
        if replace_pin(parents["2"], "0" * 64) != replace_pin(parents["3"], "0" * 64):
            raise ValueError("diagnostic workflow conflict is not limited to the reviewed project pin")
        updated = replace_pin(parents["2"], expected)
        working = repository_docs.local(root, WORKFLOW_PATH).read_bytes()
        # Keep a hand-resolved workflow; index stages must not overwrite it.
        if not CONFLICT_MARKER.search(working) and working.decode() != updated:
            raise ValueError(
                "diagnostic pin repair refuses a manually edited workflow; review and stage it explicitly"
            )
        # Only an explicit reviewed digest may update this trust boundary; never derive it here.
        return WORKFLOW_PATH, updated
    workflow = repository_docs.local(root, WORKFLOW_PATH).read_bytes()
    if staged_bytes(root, WORKFLOW_PATH) != workflow:
        raise ValueError("stage reviewed project and workflow edits first: " + WORKFLOW_PATH)
    if CONFLICT_MARKER.search(workflow):
        raise ValueError("resolve staged conflict markers first: " + WORKFLOW_PATH)
    # Only an explicit reviewed digest may update this trust boundary; never derive it here.
    return WORKFLOW_PATH, replace_pin(workflow.decode(), expected)


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
    conflicts = conflict_names(root)
    pin_update = None
    if reviewed_project_sha256 is not None:
        # The ledger stays for its own resolver. Any other unmerged path still blocks.
        extra = [name for name in conflicts if name not in {output, WORKFLOW_PATH, LEDGER_PATH}]
        if extra:
            raise ValueError("resolve source conflicts first: " + ", ".join(extra))
        pin_update = reviewed_project_pin(root, reviewed_project_sha256)
        if projection_is_unmerged(root, output):
            # A conflicted source map is rebuilt from the merged index.
            # Unstaged worktree bytes and either parent's projection cannot change fingerprints.
            errors = repository_docs.run(root)
            if errors and errors != ["source projection stale: " + output]:
                raise ValueError("; ".join(errors))
            workflow_path = repository_docs.local(root, pin_update[0])
            original_workflow = workflow_path.read_bytes()
            try:
                resolve_staged(root)
                workflow_path.write_bytes(pin_update[1].encode())
                subprocess.run(["git", "add", "--", pin_update[0]], cwd=root, check=True)
            except (OSError, subprocess.CalledProcessError, ValueError):
                workflow_path.write_bytes(original_workflow)
                raise
            print("repository-docs: regenerated and staged " + output)
            return
    else:
        unresolved = [name for name in conflicts if name != output]
        if unresolved:
            raise ValueError("resolve source conflicts first: " + ", ".join(unresolved))
        # A conflicted source map is rebuilt from the merged index.
        # Unstaged worktree bytes and either parent's projection cannot change fingerprints.
        # The worktree registry still fails closed: import and path errors are not a stale map.
        if not refresh_lockfile and not verify_lockfile and projection_is_unmerged(root, output):
            errors = repository_docs.run(root)
            if errors and errors != ["source projection stale: " + output]:
                raise ValueError("; ".join(errors))
            resolve_staged(root)
            return
    if pin_update is not None:
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
