#!/usr/bin/env python3
"""Bounded launch diagnostics; never test or release evidence. Python stdlib only."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import sys
import time

STAGES = ('launch-quality-build-for-testing', 'launch-quality-unit-tests',
          'launch-quality-ui-critical-surfaces', 'launch-quality-ui-logout-hierarchy',
          'launch-quality-ui-chaos-regressions')
PROCESSES = ('CoreSimulatorService', 'launchd_sim', 'installcoordinationd', 'installd',
             'runningboardd', 'testmanagerd', 'xcodebuild', 'LogYourBody',
             'LogYourBodyUITests-Runner')
BUNDLES = ('com.logyourbody.app.xctrunner', 'com.logyourbody.app')
MAX_BYTES = 256 * 1024
UUID = r'[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}'
EVENTS = (
    ('install_complete', r'Install successful|Installed app'),
    ('install_start', r'Installing (?:app|<MIInstallableBundle)'),
    ('launch_return', r'Launched app'),
    ('launch_start', r'Launching app|Creating and launching job'),
    ('process_active', r'running-active'),
    ('process_exit', r'process.*exit|exited with'),
    ('socket_unavailable', r'getenv returned nil'),
    ('socket_available', r'has testmanagerd socket'),
    ('session_reply', r'Got reply to.*session'),
    ('runner_ready', r'Test runner is ready|finished bootstrapping'),
    ('assertion_error', r'(?:assertion|connection).*(?:error|fail|timed out)'),
)


def timestamp():
    return {'utc': datetime.now(timezone.utc).isoformat(),
            'monotonic_seconds': time.monotonic()}


def write_json(path, value):
    temporary = path.with_suffix('.tmp')
    temporary.write_text(json.dumps(value, sort_keys=True) + '\n')
    temporary.replace(path)


def append_event(path, value, maximum=MAX_BYTES):
    encoded = (json.dumps(value, sort_keys=True) + '\n').encode()
    if (path.stat().st_size if path.exists() else 0) + len(encoded) > maximum:
        return False
    with path.open('ab') as output:
        output.write(encoded)
        output.flush()
    return True


def init(directory, stage, attempt, destination, source, patch, timeout):
    if stage not in STAGES or type(attempt) is not int or attempt not in (1, 2) or type(timeout) is not int or not 1 <= timeout <= 600:
        raise ValueError('invalid audit identity')
    revision = source.read_text().strip()
    if not re.fullmatch(r'[0-9a-f]{40}', revision):
        raise ValueError('invalid source identity')
    match = re.fullmatch(r'platform=iOS Simulator,id=(' + UUID + r')', destination)
    directory.mkdir(parents=True, exist_ok=False)
    context = {'schema': 1, 'stage': stage, 'attempt': attempt, 'source_revision': revision,
               'source_patch_sha256': hashlib.sha256(patch.read_bytes()).hexdigest(),
               'simulator_uuid': match[1].upper() if match else None,
               'audit_pid': os.getppid(), 'command_timeout_seconds': timeout,
               'architecture': os.uname().machine,
               'github_run_id': os.environ.get('GITHUB_RUN_ID', ''),
               'github_run_attempt': os.environ.get('GITHUB_RUN_ATTEMPT', '')}
    for key in ('github_run_id', 'github_run_attempt'):
        if not re.fullmatch(r'[0-9]{1,20}', context[key]):
            context[key] = None
    write_json(directory / 'context.json', context)


def mark(directory, event, status=None):
    if event not in ('command_start', 'command_end'):
        raise ValueError('invalid lifecycle event')
    row = {**timestamp(), 'event': event}
    if event == 'command_end':
        if type(status) is not int or not 0 <= status <= 255:
            raise ValueError('invalid command status')
        row['command_status'] = status
    append_event(directory / 'lifecycle.ndjson', row)


def sanitize_event(payload, origin, device):
    """Whitelist values, not redacted raw messages. Unknown text never leaves memory."""
    if not isinstance(payload, dict):
        return None
    process = Path(str(payload.get('processImagePath', ''))).name
    message = payload.get('eventMessage')
    pid = payload.get('processID')
    if process not in PROCESSES or not isinstance(message, str):
        return None
    if type(pid) is not int or not 0 < pid < 2 ** 31:
        return None
    bundle = next((b for b in BUNDLES if re.search(
        r'(?<![\w.])' + re.escape(b) + r'(?![\w.])', message)), None)
    if origin == 'host':
        if process != 'CoreSimulatorService' or not device or device.lower() not in message.lower() or not bundle:
            return None
    elif origin != 'simulator' or process == 'CoreSimulatorService' or not bundle:
        return None
    event = next((name for name, pattern in EVENTS if re.search(pattern, message, re.I)), None)
    if not event:
        return None
    try:
        value = str(payload['timestamp']).replace('Z', '+00:00')
        # Python 3.9 requires a colon in the archived numeric UTC offset.
        value = re.sub(r'([+-])([01]\d|2[0-3])([0-5]\d)$', r'\1\2:\3', value)
        instant = datetime.fromisoformat(value)
        if instant.tzinfo is None:
            return None
    except (KeyError, ValueError):
        return None
    row = {'utc': instant.astimezone(timezone.utc).isoformat(), 'origin': origin,
           'process': process, 'pid': pid, 'event': event, 'bundle': bundle,
           'observed_monotonic_seconds': time.monotonic()}
    target = re.search(r'\bpid\s*[=:]\s*(\d{1,10})\b', message, re.I)
    if target and 0 < int(target[1]) < 2 ** 31:
        row['target_pid'] = int(target[1])
    for name in ('Staging', 'Waiting', 'Preflight/Patch', 'Verifying', 'Overall'):
        match = re.search(re.escape(name) + r': (\d+(?:\.\d+)?)s\b', message)
        if match:
            seconds = float(match[1])
            if math.isfinite(seconds):
                row.setdefault('install_seconds', {})[name] = seconds
    error = re.search(r'Error Domain=(NSPOSIXErrorDomain|NSCocoaErrorDomain|NSOSStatusErrorDomain) Code=(-?\d{1,10})\b', message)
    if error:
        row['error_domain'], row['error_code'] = error[1], int(error[2])
    return row


def process_rows(text, audit_pid, associated):
    """Only the audit's xcodebuild descendants or event-bound simulator PIDs."""
    parsed = {}
    for line in text.splitlines():
        fields = line.split(None, 6)
        if len(fields) != 7:
            continue
        try:
            pid, parent = int(fields[0]), int(fields[1])
            cpu, memory = float(fields[3]), float(fields[4])
        except ValueError:
            continue
        if not (0 < pid < 2 ** 31 and 0 <= parent < 2 ** 31 and
                math.isfinite(cpu) and math.isfinite(memory) and cpu >= 0 and memory >= 0):
            continue
        if not re.fullmatch(r'[A-Za-z<>+]{1,12}', fields[2]):
            continue
        if not re.fullmatch(r'(?:\d+-)?\d{1,3}:\d{2}(?::\d{2})?', fields[5]):
            continue
        parsed[pid] = (parent, fields, cpu, memory)
    rows = []
    for pid, (parent, fields, cpu, memory) in parsed.items():
        name = Path(fields[6]).name
        ancestor = parent
        visited = set()
        while ancestor in parsed and ancestor not in visited and ancestor != audit_pid:
            visited.add(ancestor)
            ancestor = parsed[ancestor][0]
        if name not in PROCESSES or not (pid in associated or
                (name == 'xcodebuild' and ancestor == audit_pid)):
            continue
        rows.append({'pid': pid, 'ppid': parent, 'process': name, 'state': fields[2],
                     'cpu_percent': cpu, 'memory_percent': memory, 'elapsed': fields[5]})
    return rows[:32]


def commands(device, timeout):
    host = ['/usr/bin/log', 'stream', '--style', 'ndjson', '--level', 'debug',
            '--timeout', str(timeout),
            '--predicate', 'process == "CoreSimulatorService" AND eventMessage CONTAINS[c] "' + device + '"']
    predicate = '(' + ' OR '.join('process == "' + p + '"' for p in PROCESSES) + ') AND (' + ' OR '.join('eventMessage CONTAINS "' + b + '"' for b in BUNDLES) + ')'
    return {'host': host, 'simulator': ['xcrun', 'simctl', 'spawn', device, 'log',
            'stream', '--style', 'ndjson', '--level', 'debug', '--timeout', str(min(timeout, 10)),
            '--predicate', predicate]}


def stop_children(children):
    # Each host child was started in a new session. No PID-name/global kill.
    complete = True
    for child in children:
        try:
            if child.poll() is None:
                os.killpg(child.pid, signal.SIGTERM)
            try:
                child.wait(timeout=0.2)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait(timeout=0.2)
        except (OSError, subprocess.TimeoutExpired):
            complete = False
        if child.stdout:
            child.stdout.close()
    return complete


def collect(directory):
    context = json.loads((directory / 'context.json').read_text())
    device = context['simulator_uuid']
    if (context.get('schema') != 1 or context.get('stage') not in STAGES or
            type(context.get('attempt')) is not int or context['attempt'] not in (1, 2) or
            type(context.get('audit_pid')) is not int or context['audit_pid'] <= 0 or
            type(context.get('command_timeout_seconds')) is not int or
            not 1 <= context['command_timeout_seconds'] <= 600 or
            not re.fullmatch(r'[0-9a-f]{40}', str(context.get('source_revision'))) or
            (device is not None and not re.fullmatch(UUID, str(device)))):
        raise ValueError('invalid observer context')
    state = {'schema': 1, 'evidence_scope': 'diagnostics_only', 'origin_status': {},
             'discarded': 0, 'malformed': 0, 'truncated': [], 'stop': 'unknown',
             'observer_pid': os.getpid(), 'owned_host_groups': [],
             'native_completion': 'only_command_end_marker;otherwise_unknown',
             'simulator_spawn_cleanup': 'UNVERIFIED;intended_remote_timeout_at_most_10s',
             'simulator_chunks': [], 'process_frame_interval_seconds': 10}
    children = []
    selector = selectors.DefaultSelector()
    stopping = []
    prior = {sig: signal.signal(sig, lambda number, frame: stopping.append(number))
             for sig in (signal.SIGTERM, signal.SIGINT)}
    associated = set()
    deadline = time.monotonic() + context['command_timeout_seconds'] + 2
    next_snapshot = 0
    append_event(directory / 'lifecycle.ndjson', {**timestamp(), 'event': 'observer_start'})
    try:
        if not device:
            state['stop'] = 'destination_unavailable'
            return
        def start_stream(origin):
            remaining = max(1, int(deadline - time.monotonic()))
            command = commands(device, min(remaining, context['command_timeout_seconds']))[origin]
            try:
                child = subprocess.Popen(command, stdout=subprocess.PIPE,
                                         stderr=subprocess.DEVNULL, start_new_session=True)
                children.append(child)
                state['owned_host_groups'].append({'origin': origin, 'pgid': child.pid})
                os.set_blocking(child.stdout.fileno(), False)
                selector.register(child.stdout, selectors.EVENT_READ, (origin, child, bytearray()))
                state['origin_status'][origin] = 'started_not_ready'
                if origin == 'simulator':
                    state['simulator_chunks'].append({**timestamp(), 'status': 'started'})
            except OSError:
                state['origin_status'][origin] = 'unavailable'
        start_stream('host')
        start_stream('simulator')
        while selector.get_map() and not stopping and time.monotonic() < deadline:
            now = time.monotonic()
            if now >= next_snapshot:
                next_snapshot = now + 10
                try:
                    snapshot = subprocess.check_output(['/bin/ps', '-axo',
                        'pid=,ppid=,state=,pcpu=,pmem=,etime=,comm='], text=True,
                        stderr=subprocess.DEVNULL, timeout=0.5)
                    row = {**timestamp(), 'rows': process_rows(snapshot, context['audit_pid'], associated)}
                    if not append_event(directory / 'process-state.ndjson', row):
                        if 'process-state' not in state['truncated']:
                            state['truncated'].append('process-state')
                except (OSError, subprocess.SubprocessError):
                    state['process_snapshot'] = 'unavailable'
            for key, unused in selector.select(timeout=0.2):
                origin, child, buffer = key.data
                chunk = os.read(key.fileobj.fileno(), 65536)
                if not chunk:
                    selector.unregister(key.fileobj)
                    key.fileobj.close()
                    child.wait(timeout=0.2)
                    state['origin_status'][origin] = {'exited': child.returncode}
                    if origin == 'simulator':
                        state['simulator_chunks'][-1]['status'] = child.returncode
                        # Observation chunks are not native test retries. Never retry tool errors.
                        if child.returncode == 0 and not stopping and time.monotonic() < deadline:
                            if len(state['simulator_chunks']) < 60:
                                start_stream('simulator')
                            else:
                                state['truncated'].append('simulator_chunk_cap')
                    continue
                buffer.extend(chunk)
                if len(buffer) > MAX_BYTES:
                    buffer.clear()
                    state['malformed'] += 1
                while b'\n' in buffer:
                    line, unused, remainder = buffer.partition(b'\n')
                    buffer[:] = remainder
                    try:
                        event = sanitize_event(json.loads(line), origin, device)
                    except (ValueError, UnicodeError):
                        event = None
                        state['malformed'] += 1
                    if event is None:
                        state['discarded'] += 1
                        continue
                    if len(associated) < 256:
                        associated.add(event['pid'])
                        if 'target_pid' in event:
                            associated.add(event['target_pid'])
                    elif 'associated_pid_cap' not in state['truncated']:
                        state['truncated'].append('associated_pid_cap')
                    state['origin_status'][origin] = 'events_observed_not_boot_readiness'
                    if not append_event(directory / (origin + '-service-events.ndjson'), event):
                        if origin not in state['truncated']:
                            state['truncated'].append(origin)
            write_json(directory / 'collection-status.json', state)
        state['stop'] = 'signal' if stopping else 'window_elapsed_or_streams_closed'
    finally:
        state['host_wrapper_exit_observed'] = stop_children(children)
        selector.close()
        for sig, handler in prior.items():
            signal.signal(sig, handler)
        write_json(directory / 'collection-status.json', state)
        append_event(directory / 'lifecycle.ndjson', {**timestamp(), 'event': 'observer_stop',
                                                      'reason': state['stop']})


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('init', 'collect', 'mark'))
    parser.add_argument('--directory', required=True, type=Path)
    parser.add_argument('--stage', choices=STAGES)
    parser.add_argument('--attempt', type=int)
    parser.add_argument('--destination')
    parser.add_argument('--source', type=Path)
    parser.add_argument('--patch', type=Path)
    parser.add_argument('--timeout', type=int)
    parser.add_argument('--event')
    parser.add_argument('--status', type=int)
    args = parser.parse_args(argv)
    try:
        if args.mode == 'init':
            init(args.directory, args.stage, args.attempt, args.destination,
                 args.source, args.patch, args.timeout)
        elif args.mode == 'mark':
            mark(args.directory, args.event, args.status)
        else:
            collect(args.directory)
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        # Fixed stderr; paths, messages and launch environments are never printed.
        if args.mode == 'collect' and args.directory.is_dir():
            write_json(args.directory / 'collection-status.json', {
                'schema': 1, 'evidence_scope': 'diagnostics_only',
                'stop': 'collector_unavailable', 'command_end': 'unknown'})
        print('Launch diagnostics unavailable; native status is independent.', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
