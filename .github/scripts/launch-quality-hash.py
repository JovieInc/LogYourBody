#!/usr/bin/env python3
"""Content-hash and exact-hash receipt for the iOS Launch Quality audit.

Reuse is allowed only when a success receipt for this exact declared-input
hash is found. Any input change, a missing or invalid receipt, a lookup
failure, or FORCE_LAUNCH_QUALITY=1 runs the audit fully. Lookup never
fails the job: it falls back to a full run.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import tempfile
import zipfile
from datetime import datetime, timezone
from pathlib import Path

SCHEMA = "lyb-launch-quality-receipt-v1"
ARTIFACT_PREFIX = "launch-quality-receipt-"
MANIFEST_NAME = "launch-quality-inputs.json"


def repo_root() -> Path:
    env = os.environ.get("GITHUB_WORKSPACE")
    if env:
        return Path(env).resolve()
    return Path(__file__).resolve().parents[2]


def load_manifest(root: Path) -> dict:
    path = Path(__file__).resolve().parent / MANIFEST_NAME
    manifest = json.loads(path.read_text())
    if int(manifest.get("version") or 0) < 1 or not manifest.get("globs"):
        raise SystemExit(f"invalid declared-inputs manifest: {path}")
    return manifest


def glob_matches(path: str, pattern: str) -> bool:
    if pattern.endswith("/**"):
        prefix = pattern[:-3].rstrip("/")
        return path == prefix or path.startswith(prefix + "/")
    if "*" in pattern or "?" in pattern or "[" in pattern:
        import fnmatch

        return fnmatch.fnmatch(path, pattern)
    return path == pattern


def tracked_files(root: Path, globs: list[str]) -> list[str]:
    listed = subprocess.check_output(
        ["git", "-C", str(root), "ls-files", "-z"],
        text=True,
    )
    files = [name for name in listed.split("\0") if name]
    matched = [name for name in files if any(glob_matches(name, pattern) for pattern in globs)]
    return sorted(matched)


def file_digest(root: Path, relative: str) -> str:
    path = root / relative
    if path.is_symlink():
        target = os.readlink(path)
        return "symlink:" + hashlib.sha256(target.encode()).hexdigest()
    return hashlib.sha256(path.read_bytes()).hexdigest()


def declared_symlinks(root: Path, files: list[str]) -> list[str]:
    return [name for name in files if (root / name).is_symlink()]


def read_xcode_version(root: Path, manifest: dict) -> str:
    override = os.environ.get("LAUNCH_QUALITY_XCODE_VERSION")
    if override:
        return override
    spec = manifest["xcodeVersionFrom"]
    text = (root / spec["file"]).read_text()
    matches = re.findall(spec["pattern"], text)
    if len(matches) != 1:
        raise SystemExit(
            f"expected exactly one Xcode version pin in {spec['file']}, found {len(matches)}"
        )
    return matches[0]


def document_and_hash(root: Path, manifest: dict) -> tuple[str, str, str, list[str]]:
    files = tracked_files(root, manifest["globs"])
    if not files:
        raise SystemExit("declared-input globs matched no tracked files")
    xcode = read_xcode_version(root, manifest)
    lines = [
        f"manifest-version:{manifest['version']}",
        f"xcode-version:{xcode}",
    ]
    for name in files:
        lines.append(f"{name}\t{file_digest(root, name)}")
    document = "\n".join(lines) + "\n"
    digest = hashlib.sha256(document.encode()).hexdigest()
    return digest, document, xcode, files


def write_outputs(values: dict[str, str]) -> None:
    for key, value in values.items():
        print(f"{key}={value}")
    output = os.environ.get("GITHUB_OUTPUT")
    if not output:
        return
    with open(output, "a", encoding="utf8") as handle:
        for key, value in values.items():
            handle.write(f"{key}={value}\n")


def github_notice(message: str) -> None:
    print(f"::notice::{message}")


def github_warning(message: str) -> None:
    print(f"::warning::{message}")


def cmd_hash(root: Path, manifest: dict) -> int:
    digest, _, xcode, files = document_and_hash(root, manifest)
    write_outputs(
        {
            "hash": digest,
            "xcode-version": xcode,
            "input-count": str(len(files)),
            "reuse": "false",
            "reason": "hash-only",
        }
    )
    return 0


def gh_api(args: list[str], *, check: bool = True) -> subprocess.CompletedProcess:
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN") or ""
    env = os.environ.copy()
    if token and "GH_TOKEN" not in env:
        env["GH_TOKEN"] = token
    binary = os.environ.get("LQ_GH", "gh")
    return subprocess.run(
        [binary, "api", *args],
        env=env,
        check=check,
        capture_output=True,
        text=True,
    )


def load_receipt_from_zip(data: bytes, expected_hash: str) -> dict | None:
    with tempfile.TemporaryDirectory(prefix="lq-receipt-") as tmp:
        archive = Path(tmp) / "receipt.zip"
        archive.write_bytes(data)
        try:
            with zipfile.ZipFile(archive) as zipped:
                names = zipped.namelist()
                candidate = next(
                    (name for name in names if name.endswith("receipt.json") or name == "receipt.json"),
                    None,
                )
                if candidate is None:
                    return None
                payload = json.loads(zipped.read(candidate).decode())
        except (zipfile.BadZipFile, json.JSONDecodeError, UnicodeDecodeError, KeyError):
            return None
    if payload.get("schema") != SCHEMA:
        return None
    if payload.get("hash") != expected_hash:
        return None
    if payload.get("verdict") != "success":
        return None
    return payload


def lookup_receipt(repo: str, digest: str) -> dict | None:
    name = f"{ARTIFACT_PREFIX}{digest}"
    try:
        listed = gh_api([f"repos/{repo}/actions/artifacts?name={name}&per_page=10"])
    except (subprocess.CalledProcessError, UnicodeDecodeError) as error:
        github_warning(f"Launch Quality receipt lookup failed ({error}); running fully.")
        return None
    try:
        body = json.loads(listed.stdout)
        artifacts = [
            item
            for item in body.get("artifacts") or []
            if item.get("name") == name and item.get("expired") is False and item.get("id")
        ]
    except json.JSONDecodeError:
        github_warning("Launch Quality receipt listing was not JSON; running fully.")
        return None
    artifacts.sort(key=lambda item: item.get("created_at") or "", reverse=True)
    for artifact in artifacts:
        raw = gh_api_bytes(f"repos/{repo}/actions/artifacts/{artifact['id']}/zip")
        if not raw:
            continue
        payload = load_receipt_from_zip(raw, digest)
        if payload:
            return payload
    return None


def gh_api_bytes(path: str) -> bytes | None:
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN") or ""
    env = os.environ.copy()
    if token and "GH_TOKEN" not in env:
        env["GH_TOKEN"] = token
    binary = os.environ.get("LQ_GH", "gh")
    try:
        result = subprocess.run(
            [binary, "api", path],
            env=env,
            check=True,
            capture_output=True,
        )
    except subprocess.CalledProcessError:
        return None
    return result.stdout


def cmd_lookup(root: Path, manifest: dict) -> int:
    digest, _, xcode, files = document_and_hash(root, manifest)
    forced = os.environ.get("FORCE_LAUNCH_QUALITY", "") in {"1", "true", "TRUE", "yes"}
    symlinks = declared_symlinks(root, files)
    base = {
        "hash": digest,
        "xcode-version": xcode,
        "input-count": str(len(files)),
    }
    if forced:
        write_outputs({**base, "reuse": "false", "reason": "canary-or-forced-full"})
        github_notice(f"Launch Quality canary/force-full: running fully for hash {digest}.")
        return 0
    if symlinks:
        write_outputs({**base, "reuse": "false", "reason": "declared-symlink"})
        github_warning(
            "Launch Quality declared inputs include symlinks; refusing receipt reuse."
        )
        return 0
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    if not repo or not (os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")):
        write_outputs({**base, "reuse": "false", "reason": "lookup-unavailable"})
        github_notice("Launch Quality receipt lookup unavailable; running fully.")
        return 0
    try:
        receipt = lookup_receipt(repo, digest)
    except Exception as error:  # noqa: BLE001 — lookup must never fail the job
        github_warning(f"Launch Quality receipt lookup crashed ({error}); running fully.")
        write_outputs({**base, "reuse": "false", "reason": "lookup-failed"})
        return 0
    if not receipt:
        write_outputs({**base, "reuse": "false", "reason": "no-matching-receipt"})
        github_notice(f"No Launch Quality success receipt for hash {digest}; running fully.")
        return 0
    run_url = str(receipt.get("runUrl") or "")
    write_outputs(
        {
            **base,
            "reuse": "true",
            "reason": "exact-hash-receipt",
            "receipt-run-id": str(receipt.get("runId") or ""),
            "receipt-run-url": run_url,
            "receipt-head-sha": str(receipt.get("headSha") or ""),
        }
    )
    github_notice(
        f"Reusing Launch Quality success receipt for hash {digest} from {run_url or 'prior run'}."
    )
    return 0


def cmd_publish(root: Path, manifest: dict, directory: Path) -> int:
    digest, document, xcode, files = document_and_hash(root, manifest)
    if declared_symlinks(root, files):
        print("Refusing to publish a Launch Quality receipt for a tree with declared-input symlinks.", file=sys.stderr)
        return 1
    directory.mkdir(parents=True, exist_ok=True)
    head = subprocess.check_output(["git", "-C", str(root), "rev-parse", "HEAD"], text=True).strip()
    run_id = os.environ.get("GITHUB_RUN_ID", "")
    server = os.environ.get("GITHUB_SERVER_URL", "https://github.com")
    repo = os.environ.get("GITHUB_REPOSITORY", "")
    run_url = f"{server}/{repo}/actions/runs/{run_id}" if repo and run_id else ""
    receipt = {
        "schema": SCHEMA,
        "hash": digest,
        "verdict": "success",
        "headSha": head,
        "runId": run_id,
        "runUrl": run_url,
        "xcodeVersion": xcode,
        "manifestVersion": manifest["version"],
        "inputCount": len(files),
        "createdAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    (directory / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    (directory / "hash.txt").write_text(digest + "\n")
    (directory / "inputs.txt").write_text(document)
    write_outputs({"hash": digest, "xcode-version": xcode, "reuse": "false", "reason": "published"})
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["hash", "lookup", "publish"])
    parser.add_argument("--dir", type=Path, help="Directory for publish")
    parser.add_argument("--root", type=Path, help="Repository root (defaults to GITHUB_WORKSPACE or this file)")
    args = parser.parse_args(argv)
    root = (args.root or repo_root()).resolve()
    manifest = load_manifest(root)
    if args.command == "hash":
        return cmd_hash(root, manifest)
    if args.command == "lookup":
        return cmd_lookup(root, manifest)
    if not args.dir:
        raise SystemExit("publish requires --dir")
    return cmd_publish(root, manifest, args.dir)


if __name__ == "__main__":
    sys.exit(main())
