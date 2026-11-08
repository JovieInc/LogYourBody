"""Exercise both SwiftLint installers with real curl and a local HTTP server."""

import hashlib
import io
import os
import re
import subprocess
import textwrap
import threading
import zipfile
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

import pytest

from _runner_routing_fixture import _REPO_ROOT, _coverage_fds, _job_block


@pytest.mark.parametrize("installer", ["macos", "linux"])
@pytest.mark.parametrize(
    ("statuses", "fallback_statuses", "valid_archive", "checksum_matches", "success", "requests"),
    [
        ((200,), (200,), True, True, True, (1, 0)),
        ((504, 200), (200,), True, True, True, (2, 0)),
        ((504,), (200,), True, True, True, (4, 1)),
        ((504,), (504,), True, True, False, (4, 4)),
        ((504,), (403,), True, True, False, (4, 4)),
        ((504,), (403, 200), True, True, True, (4, 2)),
        ((200,), (200,), False, True, False, (1, 0)),
        ((200,), (200,), True, False, False, (1, 0)),
        ((504,), (200,), True, False, False, (4, 1)),
    ],
    ids=["success", "transient-504", "asset-api-fallback", "persistent-504",
         "forbidden-api", "transient-forbidden-api",
         "invalid-archive", "checksum-mismatch", "fallback-checksum-mismatch"],
)
def test_swiftlint_download_handles_http_failures(
    tmp_path: Path, installer: str, statuses: tuple[int, ...], fallback_statuses: tuple[int, ...],
    valid_archive: bool, checksum_matches: bool, success: bool, requests: tuple[int, int],
) -> None:
    action = (_REPO_ROOT / ".github/actions/setup-ios-build/action.yml").read_text()
    version = re.search(r'SWIFTLINT_VERSION="([^"]+)"', action)[1]
    if installer == "macos":
        step = action.split("    - name: Install SwiftLint and xcbeautify\n", 1)[1]
        indent = "      "
        url = "https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_VERSION}/portable_swiftlint.zip"
        api_url = "https://api.github.com/repos/realm/SwiftLint/releases/assets/430524024"
        checksum = "fb045e85e7cb3374f42a4840b6b85a0106302afa69035c0c6f29af4a44c810b6"
    else:
        step = _job_block("ci.yml", "ios_static").split(
            "      - name: Install SwiftLint (version pinned with setup-ios-build)\n", 1)[1]
        indent = "        "
        url = "https://github.com/realm/SwiftLint/releases/download/${version}/swiftlint_linux_amd64.zip"
        api_url = "https://api.github.com/repos/realm/SwiftLint/releases/assets/430524036"
        checksum = "26db741d43f2f2dc26c0cf16911100a3e186c3d1dbb59e55ad3ac87b0de4538f"
    assert "GH_TOKEN: ${{ github.token }}" in step.split(f"{indent}run: |\n", 1)[0]
    body = textwrap.dedent(step.split(f"{indent}run: |\n", 1)[1].split("\n    - name:", 1)[0]
                           .split("\n      - name:", 1)[0])
    body = body.replace(".github/actions/setup-ios-build/action.yml",
                        str(_REPO_ROOT / ".github/actions/setup-ios-build/action.yml"))
    binary = f"#!/usr/bin/env bash\nprintf '%s\\n' '{version}'\n"
    archive = io.BytesIO()
    with zipfile.ZipFile(archive, "w") as output:
        entry = zipfile.ZipInfo("swiftlint")
        entry.external_attr = 0o100755 << 16
        output.writestr(entry, binary)
    payload = archive.getvalue() if valid_archive else b"invalid archive"
    digest = hashlib.sha256(payload).hexdigest() if checksum_matches else "0" * 64
    body = body.replace(checksum, digest)
    observed: list[str] = []
    # Require authentication in one recovery case; other cases exercise public API access.
    token = "fixture-public-release-token" if requests == (4, 1) else ""
    headers_observed: list[tuple[str, str | None]] = []

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self) -> None:
            responses = fallback_statuses if self.path == "/asset-api.zip" else statuses
            status = responses[min(observed.count(self.path), len(responses) - 1)]
            if self.path == "/asset-api.zip":
                assert self.headers.get("Accept") == "application/octet-stream"
                if token and self.headers.get("Authorization") != f"Bearer {token}":
                    status = 403
            headers_observed.append((self.path, self.headers.get("Authorization")))
            observed.append(self.path)
            self.send_response(status)
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            # Even a valid ZIP in an HTTP error response must never be installed.
            self.wfile.write(payload)

        def log_message(self, *_args: object) -> None:
            pass

    server = HTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    assert body.count(url) == 1
    body = body.replace(url, f"http://{server.server_address[0]}:{server.server_port}/swiftlint.zip")
    body = body.replace(api_url,
                        f"http://{server.server_address[0]}:{server.server_port}/asset-api.zip")
    tools = tmp_path / "bin"
    tools.mkdir()
    for name in ("xcbeautify", "swiftlint"):
        tool = tools / name
        tool.write_text("#!/usr/bin/env bash\necho 'fixture-old-version'\n")
        tool.chmod(0o755)
    path_output = tmp_path / "github-path"
    env = {**os.environ, "PATH": f"{tools}:{os.environ['PATH']}",
           "RUNNER_TOOL_CACHE": str(tmp_path / "cache"), "GITHUB_PATH": str(path_output),
           "GITHUB_ENV": str(path_output), "RUNNER_TEMP": str(tmp_path),
           "GITHUB_WORKSPACE": str(_REPO_ROOT), "GH_TOKEN": token,
           "NO_PROXY": "127.0.0.1", "no_proxy": "127.0.0.1"}
    try:
        result = subprocess.run(
            ["bash", "-e", "-o", "pipefail", "-c", body], cwd=tmp_path, env=env,
            text=True, capture_output=True, timeout=30, check=False, pass_fds=_coverage_fds(),
        )
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
    assert (result.returncode == 0) == success, result.stdout + result.stderr
    assert observed == ["/swiftlint.zip"] * requests[0] + ["/asset-api.zip"] * requests[1]
    assert all(authorization is None for path, authorization in headers_observed if path == "/swiftlint.zip")
    if token:
        assert all(authorization == f"Bearer {token}" for path, authorization in headers_observed
                   if path == "/asset-api.zip")
    installed = (tmp_path / "cache" / "swiftlint" / version / "swiftlint" if installer == "macos"
                 else tmp_path / "swiftlint" / "swiftlint")
    if success:
        assert installed.read_text() == binary and os.access(installed, os.X_OK)
        if installer == "macos":
            assert path_output.read_text() == f"{installed.parent}\n"
        else:
            assert f"SWIFTLINT={installed}\n" in path_output.read_text()
    else:
        assert not installed.exists()
        assert not path_output.exists()
