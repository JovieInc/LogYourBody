#!/usr/bin/env python3
"""Bound an xcodebuild test command without cutting off result-bundle finalization.

The hang deadline is unchanged. A terminal XCTest result extends the deadline only until observed_at + grace.
That extension applies only when it is later than the original deadline. A run that never prints a terminal result still dies on the hang cap.
Grace cannot exceed the reviewed cap.
"""

from __future__ import annotations

import os
import select
import signal
import subprocess
import sys
import time

MAX_FINALIZATION_GRACE_SECONDS = 180
KILL_AFTER_SECONDS = 30
TERMINAL_RESULT_LINES = (
    "** TEST EXECUTE SUCCEEDED **",
    "** TEST EXECUTE FAILED **",
)


def is_terminal_result(line: str) -> bool:
    return line.strip() in TERMINAL_RESULT_LINES


def next_deadline(deadline: float, observed_at: float, grace_seconds: float, extended: bool) -> tuple[float, bool]:
    if extended:
        return deadline, True
    return max(deadline, observed_at + grace_seconds), True


def validate_budget(timeout_seconds: float, grace_seconds: float) -> None:
    if timeout_seconds <= 0 or not (0 <= grace_seconds <= MAX_FINALIZATION_GRACE_SECONDS):
        raise ValueError("xcodebuild deadline outside the reviewed cap")


def format_seconds(value: float) -> str:
    if value == int(value):
        return str(int(value))
    return str(value)


def parse_cli(argv: list[str]) -> tuple[float, float, list[str]]:
    if len(argv) < 5 or argv[0] != "--timeout-seconds" or argv[2] != "--grace-seconds" or argv[4] != "--":
        raise ValueError(
            "usage: xcodebuild-command-timeout.py --timeout-seconds N --grace-seconds N -- command"
        )
    timeout_seconds = float(argv[1])
    grace_seconds = float(argv[3])
    command = argv[5:]
    if not command:
        raise ValueError("xcodebuild deadline requires a command")
    validate_budget(timeout_seconds, grace_seconds)
    return timeout_seconds, grace_seconds, command


def _kill_group(process: subprocess.Popen[bytes], sig: signal.Signals) -> None:
    try:
        os.killpg(process.pid, sig)
    except ProcessLookupError:
        pass


def _consume(process: subprocess.Popen[bytes], sink, timeout_seconds: float, grace_seconds: float) -> str:
    assert process.stdout is not None
    fd = process.stdout.fileno()
    deadline = time.monotonic() + timeout_seconds
    extended = False
    pending = b""
    while True:
        now = time.monotonic()
        if now >= deadline:
            return "timeout"
        readable, _, _ = select.select([fd], [], [], deadline - now)
        if not readable:
            if process.poll() is not None:
                return "exit"
            continue
        try:
            chunk = os.read(fd, 65536)
        except OSError:
            return "exit"
        if not chunk:
            return "exit"
        sink.write(chunk)
        sink.flush()
        pending += chunk
        while b"\n" in pending:
            raw, pending = pending.split(b"\n", 1)
            if is_terminal_result(raw.decode("utf-8", "replace")):
                deadline, extended = next_deadline(deadline, time.monotonic(), grace_seconds, extended)


def supervise(command: list[str], timeout_seconds: float, grace_seconds: float, sink=None) -> int:
    validate_budget(timeout_seconds, grace_seconds)
    output = sys.stdout.buffer if sink is None else sink
    output.write(
        f"xcodebuild deadline {format_seconds(timeout_seconds)}s "
        f"finalization-grace {format_seconds(grace_seconds)}s\n".encode()
    )
    output.flush()
    process = subprocess.Popen(
        command,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    outcome = _consume(process, output, timeout_seconds, grace_seconds)
    if outcome == "exit":
        return process.wait()
    _kill_group(process, signal.SIGTERM)
    try:
        process.wait(timeout=KILL_AFTER_SECONDS)
    except subprocess.TimeoutExpired:
        _kill_group(process, signal.SIGKILL)
        process.wait()
    return 124


def main(argv: list[str] | None = None) -> int:
    try:
        timeout_seconds, grace_seconds, command = parse_cli(list(sys.argv[1:] if argv is None else argv))
        return supervise(command, timeout_seconds, grace_seconds)
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 64


if __name__ == "__main__":
    sys.exit(main())
