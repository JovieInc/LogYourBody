#!/usr/bin/env python3
"""Refresh generated documentation from merged or staged sources with the pinned generator."""
import argparse
import difflib
import json
import re
import subprocess
import tempfile
from contextlib import ExitStack
from pathlib import Path

import repository_docs
from manifest_union import projection_is_unmerged, restore_dependency_artifacts_on_failure


def staged_bytes(root, name):
    source = subprocess.run(
        ["git", "show", ":" + name], cwd=root, check=True, capture_output=True,
    ).stdout
    # A clean projection must not conceal unresolved markers in its staged inputs.
    if re.search(rb"(?m)^(?:<{2,}|\|{2,}|={2,}|>{2,})(?: |\r?$)", source):
        raise ValueError("resolve staged conflict markers first: " + name)
    return source


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
    # A conflicted correction ledger stays for its own resolver.
    from manifest_union import apply_manifest_union
    apply_manifest_union(root)


def union_project(root):
    """Stage insertion-only Xcode membership. Never derive the diagnostic digest."""
    from pbx_union import apply_project_union
    apply_project_union(root)


def resolve_staged(root, extra_outputs=(), expected_index=None, expected_lockfile=None, dependency_inputs=()):
    root = Path(root).resolve()
    source_index = expected_index if expected_index is not None else git_bytes(root, "ls-files", "--stage", "-z")
    # An auto-merged manifest must keep every parent test input.
    from manifest_union import assert_auto_merged_parent_inputs
    assert_auto_merged_parent_inputs(root)
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
    # Refuse a source index changed while rendering instead of staging stale parity.
    if git_bytes(root, "ls-files", "--stage", "-z") != source_index:
        raise ValueError("source index changed during projection generation; review staged inputs and retry")
    if expected_lockfile is not None and (root / "pnpm-lock.yaml").read_bytes() != expected_lockfile:
        raise ValueError("lockfile changed during projection generation; review dependency inputs and retry")
    if dependency_inputs and git_bytes(root, "diff", "--name-only", "--", *[name for name in dependency_inputs if name != "pnpm-lock.yaml"]):
        raise ValueError("dependency inputs changed during projection generation; stage reviewed inputs and retry")
    output.parent.mkdir(parents=True, exist_ok=True)
    original = output.read_bytes() if output.exists() else None
    try:
        output.write_bytes(projection)
        subprocess.run(["git", "add", "--", config["output"], *extra_outputs], cwd=root, check=True)
    except (OSError, subprocess.CalledProcessError):
        # Keep failed staging retryable, including the original conflict markers.
        if original is None:
            output.unlink(missing_ok=True)
        else:
            output.write_bytes(original)
        raise
    print("repository-docs: regenerated and staged " + config["output"] + " from index")


DIAGNOSTIC_PROJECT = "apps/ios/LogYourBody.xcodeproj/project.pbxproj"
DIAGNOSTIC_WORKFLOW = ".github/workflows/ios-ui-diagnostics.yml"
DIAGNOSTIC_PIN = re.compile(
    r"(?m)^( +'" + re.escape(DIAGNOSTIC_PROJECT) + r"': ')[0-9a-f]{64}(',)$"
)


def git_bytes(root, *args):
    return subprocess.run(
        ["git", *args], cwd=root, check=True, capture_output=True,
    ).stdout


def conflicted_diagnostic_template(root, explicit_audit=None):
    """Return branch workflow text for pin conflicts and one-sided dependency lines.

    Keep branch edits when incoming changed only this project pin.
    """
    entries = [
        entry for entry in git_bytes(
            root, "ls-files", "--unmerged", "-z", "--", DIAGNOSTIC_WORKFLOW,
        ).decode().split("\0") if entry
    ]
    stages = [entry.split("\t", 1)[0].split() for entry in entries]
    if len(stages) != 3 or {row[2] for row in stages if len(row) == 3} != {"1", "2", "3"}:
        raise ValueError("diagnostic pin repair requires all three workflow stages")
    if any(row[0] not in {"100644", "100755"} for row in stages):
        raise ValueError("diagnostic pin repair requires a regular workflow file")
    texts = []
    for stage in ("1", "2", "3"):
        text = git_bytes(root, "show", f":{stage}:{DIAGNOSTIC_WORKFLOW}").decode()
        if re.search(r"(?m)^(?:<{2,}|\|{2,}|={2,}|>{2,})(?: |\r?$)", text):
            raise ValueError("diagnostic pin repair refuses conflict markers in a parent")
        texts.append(text)
    from reviewed_audit_pin import conflicted_pin_template
    worktree = repository_docs.local(root, DIAGNOSTIC_WORKFLOW).read_text()
    return conflicted_pin_template(
        texts[0], texts[1], texts[2], DIAGNOSTIC_PIN, explicit_audit, worktree,
    )


PBX_MEMBER = re.compile(
    r"(?m)^\t\t([A-Za-z0-9]+) /\* .*? \*/ = \{isa = PBX(?:BuildFile|FileReference);"
)
PBX_BUILD_FILE = re.compile(
    r"(?m)^\t\t([A-Za-z0-9]+) /\* .*? \*/ = \{isa = PBXBuildFile; fileRef = ([A-Za-z0-9]+)\b"
)


def assert_merged_project_keeps_parent_files(root, project):
    """A merged diagnostic project must keep every parent file membership."""
    if subprocess.run(
        ["git", "rev-parse", "--verify", "MERGE_HEAD"], cwd=root, capture_output=True,
    ).returncode:
        raise ValueError("diagnostic pin repair requires an active merge")
    base_rev = subprocess.run(
        ["git", "merge-base", "HEAD", "MERGE_HEAD"],
        cwd=root, check=True, capture_output=True, text=True,
    ).stdout.strip()

    def blob(spec):
        try:
            return git_bytes(root, "show", spec).decode()
        except subprocess.CalledProcessError as error:
            raise ValueError("diagnostic pin repair cannot read " + spec) from error
        except UnicodeDecodeError as error:
            raise ValueError("diagnostic project is not text: " + spec) from error

    base_ids = set(PBX_MEMBER.findall(blob(f"{base_rev}:{DIAGNOSTIC_PROJECT}")))
    added = set()
    parent_sources = []
    for parent in ("HEAD", "MERGE_HEAD"):
        source = blob(f"{parent}:{DIAGNOSTIC_PROJECT}")
        parent_sources.append(source)
        added.update(set(PBX_MEMBER.findall(source)) - base_ids)
    try:
        merged = project.decode()
        merged_ids = set(PBX_MEMBER.findall(merged))
    except UnicodeDecodeError as error:
        raise ValueError("diagnostic project is not text") from error
    missing = sorted(added - merged_ids)
    if missing:
        raise ValueError("merged project dropped a parent file: " + ", ".join(missing))
    # Identifier counts cannot detect a build entry rewired to the wrong file.
    merged_edges = dict(PBX_BUILD_FILE.findall(merged))
    for source in parent_sources:
        for identifier, file_ref in PBX_BUILD_FILE.findall(source):
            if identifier in added and merged_edges.get(identifier) != file_ref:
                raise ValueError("merged project changed a parent build-file mapping: " + identifier)
    # Declarations alone cannot prove that group and build-phase references survived.
    for identifier in sorted(added):
        token = re.compile(r"\b" + re.escape(identifier) + r"\b")
        expected = max(len(token.findall(source)) for source in parent_sources)
        if len(token.findall(merged)) < expected:
            raise ValueError("merged project dropped a parent file reference: " + identifier)


def reviewed_conflicted_pin(root, expected, explicit_audit=None):
    if not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise ValueError("reviewed project SHA-256 must be 64 lowercase hex characters")
    for name in (DIAGNOSTIC_PROJECT, DIAGNOSTIC_WORKFLOW):
        path = root / name
        if any(parent.is_symlink() for parent in (path, *path.parents) if parent != root.parent):
            raise ValueError("reviewed project repair refuses symlinks: " + name)
    try:
        project = staged_bytes(root, DIAGNOSTIC_PROJECT)
    except subprocess.CalledProcessError as error:
        raise ValueError("resolve source conflicts first: " + DIAGNOSTIC_PROJECT) from error
    if re.search(rb"(?m)^(?:<{2,}|\|{2,}|={2,}|>{2,})(?: |\r?$)", project):
        raise ValueError("resolve staged conflict markers first: " + DIAGNOSTIC_PROJECT)
    assert_merged_project_keeps_parent_files(root, project)
    if repository_docs.digest(project) != expected:
        raise ValueError("reviewed project SHA-256 does not match merged source")
    routing = None
    if explicit_audit is not None:
        from reviewed_audit_pin import assert_staged_audit, conflicted_routing_text
        assert_staged_audit(root, explicit_audit)
        routing = conflicted_routing_text(root, explicit_audit)
    template = conflicted_diagnostic_template(root, explicit_audit)
    # A conflicted diagnostic pin is replaced only by the reviewed project digest.
    # Only an explicit reviewed digest may update this trust boundary; never derive it here.
    updated, count = DIAGNOSTIC_PIN.subn(
        lambda match: match.group(1) + expected + match.group(2), template, count=1,
    )
    if count != 1:
        raise ValueError("expected exactly one diagnostic project pin")
    return DIAGNOSTIC_WORKFLOW, updated, routing


def stage_conflicted_diagnostic_pin(root, pin_update, output):
    from reviewed_audit_pin import stage_resolved_pins
    stage_resolved_pins(root, pin_update, output, resolve_staged, git_bytes)


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


def apply_reviewed_audit_pins(root, expected):
    """Only an explicit reviewed audit digest may update every current pin."""
    from reviewed_audit_pin import apply_pins
    apply_pins(root, expected, resolve_staged)


def resolve(root, refresh_lockfile=False, verify_lockfile=False, reviewed_project_sha256=None,
            reviewed_audit_sha256=None):
    root = Path(root).resolve()
    config = json.loads(repository_docs.local(root, "repository-docs.json").read_text())
    output = repository_docs.local(root, config["output"]).relative_to(root).as_posix()
    conflicts = subprocess.run(
        ["git", "diff", "--name-only", "--diff-filter=U", "--relative", "-z"],
        cwd=root, check=True, capture_output=True,
    ).stdout.decode().split("\0")
    # A conflicted correction ledger stays for its own resolver.
    from manifest_union import LEDGER
    unresolved = sorted(set(conflicts) - {"", output, LEDGER})
    conflicted_pin = None
    if reviewed_project_sha256 is not None and DIAGNOSTIC_WORKFLOW in unresolved:
        conflicted_pin = reviewed_conflicted_pin(
            root, reviewed_project_sha256, reviewed_audit_sha256,
        )
        drop = {DIAGNOSTIC_WORKFLOW}
        if conflicted_pin[2] is not None:
            drop.add("scripts/tests/test_runner_routing.py")
        unresolved = [name for name in unresolved if name not in drop]
    if unresolved:
        raise ValueError("resolve source conflicts first: " + ", ".join(unresolved))
    if conflicted_pin is not None:
        stage_conflicted_diagnostic_pin(root, conflicted_pin, output)
        return
    if reviewed_audit_sha256 is not None:
        apply_reviewed_audit_pins(root, reviewed_audit_sha256)
        return
    # A conflicted source map is rebuilt from the merged index.
    # Unstaged worktree bytes and either parent's projection cannot change fingerprints.
    # The worktree registry still fails closed: import and path errors are not a stale map.
    if (
        not refresh_lockfile
        and not verify_lockfile
        and reviewed_project_sha256 is None
        and reviewed_audit_sha256 is None
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
            # Pnpm hooks, workspace npmrc files and patches also affect dependency resolution.
            # Projection configuration must be staged before dependency verification.
            inputs = ["package.json", "**/package.json", "pnpm-workspace.yaml",
                      "pnpm-lock.yaml", ".npmrc", "**/.npmrc", ".pnpmfile.cjs",
                      "**/.pnpmfile.cjs", "patches/**", "repository-docs.json", output]
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
            # Ignored hooks, npmrc files and patches are still local-only resolver inputs.
            # Ignored workspace manifests are still local-only resolver inputs.
            ignored = subprocess.run(
                ["git", "ls-files", "--others", "--ignored", "--exclude-standard", "-z", "--",
                 ".npmrc", "**/.npmrc", ".pnpmfile.cjs", "**/.pnpmfile.cjs", "patches/**",
                 "package.json", "**/package.json",
                 ":(glob,exclude)**/node_modules/**", ":(glob,exclude)**/.next/**"],
                cwd=root, check=True, capture_output=True, text=True,
            ).stdout.strip("\0")
            if ignored:
                raise ValueError("ignored dependency inputs: " + ignored.replace("\0", ", "))
            # Dependency resolution inputs must be regular indexed files, never symlinks.
            for entry in git_bytes(root, "ls-files", "--stage", "-z", "--", *inputs).split(b"\0"):
                if entry and entry.split(b" ", 1)[0] not in {b"100644", b"100755"}:
                    name = entry.split(b"\t", 1)[1].decode()
                    raise ValueError("dependency input must be a regular indexed file: " + name)
            # Refuse pinned-source drift before invoking the dependency resolver.
            errors = repository_docs.run(root)
            if errors and errors != ["source projection stale: " + output]:
                raise ValueError("; ".join(errors))
            rollback.enter_context(restore_dependency_artifacts_on_failure(root, output))
            verified_index = git_bytes(root, "ls-files", "--stage", "-z")
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
            # Refuse inputs changed during verification before staging dependency artifacts.
            if (git_bytes(root, "ls-files", "--stage", "-z") != verified_index
                    or git_bytes(root, "diff", "--name-only", "--",
                                 *[name for name in inputs if name != "pnpm-lock.yaml" or verify_lockfile or not modes])):
                raise ValueError("dependency inputs changed during verification; stage reviewed inputs and retry")
            # Dependency repairs fingerprint only staged sources, preserving unrelated edits.
            resolve_staged(root, ["pnpm-lock.yaml"] if refresh_lockfile else [], expected_index=verified_index,
                           expected_lockfile=(root / "pnpm-lock.yaml").read_bytes(), dependency_inputs=inputs)
            return
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
    mode.add_argument("--merge-sections", metavar="PATH", help="print a proposed docs merge retaining the branch plus new incoming sections; review and stage explicitly")
    mode.add_argument("--union-manifests", action="store_true", help="keep every parent shared-lib test input and turbo string, then regenerate the source projection")
    mode.add_argument("--union-project", action="store_true", help="union additive Xcode file membership from both parents and stage the project")
    mode.add_argument("--merge-ledger", action="store_true", help="refresh staged docs, then preserve and classify both merge parents' correction receipts")
    parser.add_argument("--reviewed-project-sha256", help="refresh the diagnostic project pin using an explicitly reviewed merged-project digest")
    parser.add_argument("--reviewed-audit-sha256", help="refresh every current reviewed audit pin using an explicitly reviewed audit digest")
    args = parser.parse_args()
    exclusive = any((
        args.staged, args.refresh_lockfile, args.verify_lockfile, args.merge_sections,
        args.union_manifests, args.union_project, args.merge_ledger,
    ))
    if exclusive and (args.reviewed_project_sha256 or args.reviewed_audit_sha256):
        parser.error("reviewed digests cannot be combined with another repair mode")
    try:
        if args.merge_sections:
            print(merge_sections(args.root, args.merge_sections), end="")
        elif args.merge_ledger:
            from manifest_union import merge_ledger
            merge_ledger(args.root, resolve_staged, staged_bytes, git_bytes)
        elif args.union_project:
            union_project(args.root)
        elif args.union_manifests:
            union_manifests(args.root)
            resolve(args.root)
        elif args.staged:
            resolve_staged(args.root)
        else:
            resolve(args.root, args.refresh_lockfile, args.verify_lockfile,
                    args.reviewed_project_sha256, args.reviewed_audit_sha256)
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as exc:
        parser.exit(1, "repository-docs: " + str(exc) + "\n")


if __name__ == "__main__":
    main()
