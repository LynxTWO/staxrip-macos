"""Unbundled development process caller; no native app, import or publication API.

Explicit operator-trusted executable only. Cancellation terminates the owned process;
partial components remain in the caller-owned stage for cleanup after settlement.
"""
import contextlib
import hashlib
import os
import secrets
import signal
import stat
import subprocess
import threading
import time

import check

LINE_LIMIT = 16384
KEYS = {'kind', 'protocol', 'operation', 'retention', 'source_file_id', 'stage_file_id',
        'source_bytes', 'source_sha256', 'packets', 'records', 'enhancement_nals',
        'components', 'heap_limit', 'peak_heap_bytes', 'semantic_verification'}


def file_id(info):
    return [info.st_dev, info.st_ino]


def directory_id(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_uid)


@contextlib.contextmanager
def owned_process(argv, cancel, timeout):
    check.require(0 < timeout <= 120, 'Development writer deadline bound')
    check.require(not cancel.is_set(), 'Writer cancelled')
    child = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                             stderr=subprocess.DEVNULL, start_new_session=True)
    done = threading.Event()
    aborted = threading.Event()
    deadline = time.monotonic() + timeout
    lifecycle = threading.Lock()

    def stop_owned():
        try:
            os.killpg(child.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        except PermissionError:
            if child.poll() is None:
                try:
                    child.kill()
                except ProcessLookupError:
                    pass

    def watch():
        while not done.wait(0.01):
            with lifecycle:
                if done.is_set():
                    return
                if cancel.is_set() or time.monotonic() >= deadline:
                    aborted.set()
                    stop_owned()
                    return
    watcher = threading.Thread(target=watch, name='development-companion-owner')
    watcher.start()

    def read():
        data = child.stdout.readline(LINE_LIMIT + 1)
        check.require(not aborted.is_set() and not cancel.is_set(), 'Writer cancelled or expired')
        check.require(data and len(data) <= LINE_LIMIT and data.endswith(b'\n'), 'Invalid writer frame')
        value = check.decode(data)
        check.require(type(value) is dict, 'Writer frame is not an object')
        return value
    def finish():
        # Reap and disarm under the same lock used by the cancellation monitor.
        # EOF alone is insufficient: a process can close stdout and remain alive.
        while True:
            with lifecycle:
                code = child.poll()
                if code is not None:
                    done.set()
                    return code
            done.wait(0.01)
    try:
        yield child, read, aborted, finish
    finally:
        with lifecycle:
            done.set()
        watcher.join()  # No monitor can signal a PID after direct-child reaping.
        if child.returncode is None:
            stop_owned()  # Includes a pipe-holding descendant of an exited direct child.
        for stream in (child.stdin, child.stdout):
            try:
                stream.close()
            except OSError:
                pass
        child.wait()


def checked_content(fd, cancel):
    size = os.fstat(fd).st_size
    digest = hashlib.sha256()
    for offset in range(0, size, 1 << 20):
        check.require(not cancel.is_set(), 'Writer cancelled')
        data = check.read_at(fd, offset, min(1 << 20, size - offset))
        check.require(not cancel.is_set(), 'Writer cancelled')
        digest.update(data)
    check.require(not cancel.is_set(), 'Writer cancelled')
    return size, digest.hexdigest()


def produce(source, stage, executable, retention, *, cancel=None, timeout=120):
    return _produce(source, stage, executable, retention, cancel or threading.Event(), timeout, lambda: None)


def _produce(source, stage, executable, retention, cancel, timeout, after_ready):
    check.require(retention in ('metadata', 'full'), 'Unknown retention')
    check.require(not cancel.is_set(), 'Writer cancelled')
    with contextlib.ExitStack() as stack:
        source_fd = check.open_regular(source, check.FILE_LIMIT)
        stack.callback(os.close, source_fd)
        source_before = check.identity(os.fstat(source_fd))
        directory = os.open(stage, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
        stack.callback(os.close, directory)
        info = os.fstat(directory)
        check.require(stat.S_ISDIR(info.st_mode) and info.st_uid == os.geteuid()
                      and info.st_mode & 0o7777 == 0o700, 'Unsafe stage')
        stage_before = directory_id(info)
        check.require(directory_id(os.stat(stage, follow_symlinks=False)) == stage_before
                      and not os.listdir(directory), 'Stage changed or not empty')
        operation = secrets.token_hex(16)
        source_id = file_id(os.fstat(source_fd))
        stage_id = file_id(info)
        argv = [executable, retention, source, stage, operation, *map(str, source_id + stage_id)]
        with owned_process(argv, cancel, timeout) as (child, read, aborted, finish):
            check.require(check.same_json(read(), dict(kind='ready', protocol=1, operation=operation)),
                          'Wrong writer readiness')
            after_ready()  # Private generated fault boundary; public caller has no hook.
            check.require(not cancel.is_set() and not aborted.is_set(), 'Writer cancelled')
            child.stdin.write(('start ' + operation + '\n').encode())
            child.stdin.close()
            result = read()
            check.require(child.stdout.read(1) == b'', 'Trailing writer output')
            check.require(finish() == 0 and not aborted.is_set() and not cancel.is_set(),
                          'Writer did not complete')
        check.require(set(result) == KEYS and result['kind'] == 'staged'
                      and type(result['protocol']) is int and result['protocol'] == 1
                      and result['operation'] == operation and result['retention'] == retention
                      and result['semantic_verification'] is False, 'Wrong staged receipt')
        for name, expected in [('source_file_id', source_id), ('stage_file_id', stage_id)]:
            value = result[name]
            check.require(type(value) is list and len(value) == 2, 'Wrong file identity')
            for n in value:
                check.integer(n, 0, (1 << 64) - 1)
            check.require(value == expected, 'Changed file identity')
        check.integer(result['source_bytes'], 1)
        check.require(result['source_bytes'] == os.fstat(source_fd).st_size, 'Wrong source length')
        check.digest(result['source_sha256'])
        for name in ('packets', 'records'):
            check.integer(result[name], 1, check.COUNT_LIMIT)
        check.integer(result['enhancement_nals'], 0, check.COUNT_LIMIT ** 2)
        check.integer(result['heap_limit'], 64 << 20, 64 << 20)
        check.integer(result['peak_heap_bytes'], 1, 64 << 20)
        limits = dict(check.LIMITS, **{'manifest.json': 1 << 20})
        if retention == 'metadata':
            del limits['original-container.mkv']
        check.require(type(result['components']) is list and len(result['components']) == len(limits),
                      'Wrong component count')
        check.require(set(os.listdir(directory)) == set(limits), 'Wrong stage members')
        final_directory = check.identity(os.fstat(directory))
        opened = {}
        for item in result['components']:
            check.require(type(item) is dict and set(item) == {'name', 'bytes', 'sha256'}, 'Wrong component fields')
            name = item['name']
            check.require(type(name) is str and name in limits and name not in opened, 'Wrong component name')
            check.integer(item['bytes'], 1, limits[name])
            check.digest(item['sha256'])
            fd = check.open_regular(name, limits[name], directory, True)
            stack.callback(os.close, fd)
            before = os.fstat(fd)
            check.require(before.st_uid == os.geteuid() and before.st_mode & 0o7777 == 0o600,
                          'Unsafe component permissions')
            check.require(checked_content(fd, cancel) == (item['bytes'], item['sha256']), 'Wrong disk content')
            opened[name] = (fd, check.identity(before))
            check.require(not cancel.is_set(), 'Writer cancelled')
        check.require(directory_id(os.fstat(directory)) == stage_before
                      and check.identity(os.fstat(directory)) == final_directory
                      and check.identity(os.stat(stage, follow_symlinks=False)) == final_directory
                      and set(os.listdir(directory)) == set(limits), 'Changed stage')
        for name, (fd, before) in opened.items():
            check.require(check.identity(os.fstat(fd)) == before
                          and check.identity(os.stat(name, dir_fd=directory, follow_symlinks=False)) == before,
                          'Changed staged component')
        check.require(check.identity(os.fstat(source_fd)) == source_before
                      and check.identity(os.stat(source, follow_symlinks=False)) == source_before,
                      'Changed source')
        check.require(not cancel.is_set(), 'Writer cancelled')
        return result  # Still requires independent semantic verification and publication.
