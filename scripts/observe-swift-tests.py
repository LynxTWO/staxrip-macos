#!/usr/bin/env python3
"""Read-only, bounded observation of this workflow's generated test process."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

root_pid = int(sys.argv[1])
output = Path(sys.argv[2])
output.mkdir(parents=True, exist_ok=True)
started = time.monotonic()


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def descendants():
    result = subprocess.run(['/bin/ps', '-axo', 'pid=,ppid=,comm='], capture_output=True, text=True, timeout=5, check=True)
    rows = []
    for line in result.stdout.splitlines():
        values = line.strip().split(None, 2)
        if len(values) == 3:
            rows.append((int(values[0]), int(values[1]), Path(values[2]).name))
    selected = {root_pid}
    for _ in range(16):
        children = {pid for pid, parent, _ in rows if parent in selected}
        if children <= selected:
            break
        selected |= children
    return [(pid, parent, name) for pid, parent, name in rows if pid in selected]


def observe():
    target = None
    while time.monotonic() - started < 300 and alive(root_pid):
        candidates = [(pid, name) for pid, _, name in descendants()
                      if name == 'swiftpm-testing-helper' or name == 'StaxRipMacPackageTests']
        if candidates:
            target = candidates[0]
            break
        time.sleep(1)
    if target is None:
        return {'observed': False, 'reason': 'No owned test process found within bounded discovery.'}
    found = time.monotonic()
    while time.monotonic() - found < 30:
        if not alive(root_pid) or not alive(target[0]):
            return {'observed': False, 'reason': 'Test exited before observation window.'}
        time.sleep(1)
    rows = descendants()
    if target[0] not in {pid for pid, _, _ in rows}:
        return {'observed': False, 'reason': 'Test process ownership changed.'}
    # No arguments or environment values are requested. Names are basenames only.
    selected = [(pid, parent, name) for pid, parent, name in rows
                if name in ('ffmpeg', 'ffprobe', 'swiftpm-testing-helper', 'StaxRipMacPackageTests')]
    pids = ','.join(str(pid) for pid, _, _ in selected[:128])
    stats = subprocess.run(['/bin/ps', '-p', pids, '-o', 'pid=,ppid=,state=,pcpu=,rss='], capture_output=True, text=True, timeout=5)
    cpu = subprocess.check_output(['/usr/sbin/sysctl', '-n', 'hw.ncpu'], text=True, timeout=5).strip()
    report = {'observed': True, 'cpuCount': int(cpu), 'elapsedFromProcessDiscovery': time.monotonic() - found,
              'processes': selected[:128], 'totalSelectedProcesses': len(selected), 'stats': stats.stdout,
              'sampleSeconds': 1, 'sampleIntervalMilliseconds': 10}
    sample = output / 'test-process.sample.txt'
    sample_start = time.monotonic()
    result = subprocess.run(['/usr/bin/sample', str(target[0]), '1', '10', '-file', str(sample)],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=15)
    report['sampleExitCode'] = result.returncode
    report['sampleElapsedSeconds'] = time.monotonic() - sample_start
    if sample.exists() and sample.stat().st_size > 8 * 1024 * 1024:
        with sample.open('rb') as handle:
            bounded = handle.read(8 * 1024 * 1024)
        sample.write_bytes(bounded)
        report['sampleTruncated'] = True
    return report


try:
    report = observe()
except Exception as error:
    report = {'observed': False, 'reason': type(error).__name__}
(output / 'observation.json').write_text(json.dumps(report, indent=2))
print('HOSTED_TIMING ' + json.dumps(report), flush=True)
