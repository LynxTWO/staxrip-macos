"""Read-only generated-development verifier, not a native or stable archive importer.

The independently supplied helper must be the trusted development Rust reader. Never
take executable paths from a package. Boundary observations do not freeze a source or
defend against a same-user adversary. No decoded-picture qualification is implied.
"""
import argparse
import contextlib
import hashlib
import json
import os
import signal
import stat
import subprocess
import threading

FILE_LIMIT = 1 << 40
COUNT_LIMIT = 2_000_000
LINE_LIMIT = 65536
LIMITS = {
    "original-track-entry-payload.bin": 1 << 20,
    "hevc-configuration.bin": 1 << 20,
    "original-rpu.bin": 1 << 29,
    "rpu-index.jsonl": 1 << 29,
    "source-audit.jsonl": 1 << 30,
    "original-container.mkv": FILE_LIMIT,
}
MANIFEST_KEYS = {
    "kind", "version", "retention", "source_bytes", "source_sha256",
    "track_payload_original_offset", "packets", "records", "enhancement_nals",
    "association", "decoded_frame_association", "source_content_recheck",
    "source_path_identity_bound", "metadata_rewritten", "components",
}


class Refused(ValueError):
    pass


def require(value, message):
    if not value:
        raise Refused(message)


def pairs(items):
    result = {}
    for key, value in items:
        require(key not in result, "Duplicate JSON field")
        result[key] = value
    return result


def decode(data):
    try:
        return json.loads(data, object_pairs_hook=pairs,
                          parse_constant=lambda _: (_ for _ in ()).throw(Refused("Nonfinite JSON")))
    except (UnicodeError, json.JSONDecodeError, RecursionError) as error:
        raise Refused("Invalid JSON") from error


def integer(value, minimum=0, maximum=FILE_LIMIT):
    require(type(value) is int and minimum <= value <= maximum, "Integer outside bounds")
    return value


def digest(value):
    require(type(value) is str and len(value) == 64
            and all(c in "0123456789abcdef" for c in value), "Invalid digest")


def same_json(a, b):
    # Python equality treats True as 1; archive JSON must preserve numeric types.
    return json.dumps(a, sort_keys=True) == json.dumps(b, sort_keys=True)


def identity(info):
    return (info.st_dev, info.st_ino, info.st_mode, info.st_nlink, info.st_size,
            info.st_mtime_ns, info.st_ctime_ns)


def read_at(fd, offset, size):
    integer(offset)
    integer(size)
    require(offset + size <= os.fstat(fd).st_size, "Read outside component")
    data = os.pread(fd, size, offset)
    require(len(data) == size, "Short component read")
    return data


def content(fd):
    size = os.fstat(fd).st_size
    h = hashlib.sha256()
    for offset in range(0, size, 1 << 20):
        h.update(read_at(fd, offset, min(1 << 20, size - offset)))
    return size, h.hexdigest()


def open_regular(name, limit, directory=None, single_link=False):
    fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC,
                 dir_fd=directory)
    try:
        info = os.fstat(fd)
        require(stat.S_ISREG(info.st_mode) and 0 < info.st_size <= limit, "Not a bounded regular file")
        require(not single_link or info.st_nlink == 1, "Linked package component")
        require(identity(info) == identity(os.stat(name, dir_fd=directory, follow_symlinks=False)),
                "Path identity changed")
        return fd
    except BaseException:
        os.close(fd)
        raise


def rows(fd):
    # Dup shares offset; each stream has a single owner and starts at zero.
    os.lseek(fd, 0, os.SEEK_SET)
    with os.fdopen(os.dup(fd), "rb") as stream:
        for index in range(2 * COUNT_LIMIT + 4):
            line = stream.readline(LINE_LIMIT + 1)
            if not line:
                return
            require(len(line) <= LINE_LIMIT and line.endswith(b"\n"), "Unbounded or incomplete row")
            value = decode(line)
            require(type(value) is dict, "Row is not an object")
            yield value
        raise Refused("Too many rows")


def element(fd, offset, end):
    """Small independent EBML walker; unknown size is allowed only by its caller."""
    require(offset < end, "Missing EBML element")
    first = read_at(fd, offset, 1)[0]
    require(first != 0, "Invalid EBML ID")
    width = 9 - first.bit_length()
    require(width <= 4 and offset + width < end, "EBML ID bound")
    tag = int.from_bytes(read_at(fd, offset, width), "big")
    position = offset + width
    first = read_at(fd, position, 1)[0]
    require(first != 0, "Invalid EBML size")
    width = 9 - first.bit_length()
    require(width <= 8 and position + width <= end, "EBML size bound")
    raw = read_at(fd, position, width)
    length = int.from_bytes(raw, "big") & ((1 << (7 * width)) - 1)
    start = position + width
    unknown = length == (1 << (7 * width)) - 1
    stop = end if unknown else start + length
    require(stop <= end, "EBML child outside parent")
    return tag, start, stop, unknown


def children(fd, start, end):
    count = 0
    while start < end:
        require(count < 100000, "EBML element count bound")
        tag, payload, stop, unknown = element(fd, start, end)
        require(not unknown, "Unknown-sized child")
        yield tag, payload, stop
        start = stop
        count += 1


def selected_track(fd):
    size = os.fstat(fd).st_size
    tag, _, end, unknown = element(fd, 0, size)
    require(tag == 0x1A45DFA3 and not unknown, "Missing EBML header")
    tag, start, end, _ = element(fd, end, size)
    require(tag == 0x18538067, "Missing segment")
    selected = None
    tracks_seen = False
    for tag, payload, stop in children(fd, start, end):
        if tag == 0x1F43B675:
            break  # Independent configuration location, not packet parsing.
        if tag != 0x1654AE6B:
            continue
        require(not tracks_seen, "Repeated tracks")
        tracks_seen = True
        for entry, a, b in children(fd, payload, stop):
            if entry != 0xAE:
                continue
            require(b - a <= 1 << 20, "Track payload bound")
            fields = {}
            for key, c, d in children(fd, a, b):
                if key in (0xD7, 0x83, 0x86, 0x63A2):
                    require(key not in fields, "Duplicate critical track field")
                    fields[key] = read_at(fd, c, d - c)
            if int.from_bytes(fields.get(0x83, b""), "big") != 1:
                continue
            require(selected is None, "Multiple video tracks")
            require(fields.get(0x86) == b"V_MPEGH/ISO/HEVC" and 0x63A2 in fields,
                    "Unsupported selected track")
            number = int.from_bytes(fields.get(0xD7, b""), "big")
            integer(number, 1)
            selected = (a, read_at(fd, a, b - a), fields[0x63A2], number)
    require(selected is not None, "No selected track")
    return selected


@contextlib.contextmanager
def helper_rows(helper, source, timeout):
    # Trusted, explicit development helper. Arguments are never from the manifest.
    process = subprocess.Popen([helper, "mkv-summary", source], stdin=subprocess.DEVNULL,
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                               start_new_session=True)
    expired = threading.Event()
    def stop_owned():
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        except PermissionError:
            # Darwin can refuse signaling a group whose fast child already exited.
            # Reap that child; if still live, kill our direct child explicitly.
            if process.poll() is None:
                process.kill()
    def terminate():
        expired.set()
        stop_owned()
    timer = threading.Timer(timeout, terminate)
    timer.start()
    def output():
        for _ in range(2 * COUNT_LIMIT + 4):
            line = process.stdout.readline(LINE_LIMIT + 1)
            if not line:
                return
            require(not expired.is_set(), "Helper deadline")
            require(len(line) <= LINE_LIMIT and line.endswith(b"\n"), "Invalid helper row")
            row = decode(line)
            require(type(row) is dict, "Invalid helper object")
            yield row
        raise Refused("Helper row count bound")
    try:
        yield output()
        require(process.wait() == 0 and not expired.is_set(), "Helper did not complete")
    finally:
        timer.cancel()
        try:
            if process.returncode is None:
                stop_owned()  # Includes descendants keeping the pipe open.
        finally:
            process.stdout.close()
            process.wait()
            timer.join()


def validate(source, package, helper, *, timeout=120):
    require(0 < timeout <= 120, "Helper deadline bound")
    with contextlib.ExitStack() as stack:
        source_fd = open_regular(source, FILE_LIMIT)
        stack.callback(os.close, source_fd)
        source_before = identity(os.fstat(source_fd))
        source_content = content(source_fd)
        directory = os.open(package, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
        stack.callback(os.close, directory)
        directory_before = identity(os.fstat(directory))
        require(directory_before == identity(os.stat(package, follow_symlinks=False)), "Package changed")
        manifest_fd = open_regular("manifest.json", 1 << 20, directory, True)
        stack.callback(os.close, manifest_fd)
        manifest_content = content(manifest_fd)
        manifest_before = identity(os.fstat(manifest_fd))
        m = decode(read_at(manifest_fd, 0, manifest_content[0]))
        require(type(m) is dict and set(m) == MANIFEST_KEYS, "Unknown manifest fields")
        require(m["kind"] == "development-original-companion" and type(m["version"]) is int
                and m["version"] == 0, "Unknown manifest version")
        require(m["association"] == "original-encoded-packet-order"
                and m["decoded_frame_association"] == "not-established"
                and m["source_content_recheck"] is True
                and m["source_path_identity_bound"] is False
                and m["metadata_rewritten"] is False, "Unsupported qualification flags")
        mode = m["retention"]
        require(mode in ("entire-original-container", "rpu-and-original-track-metadata-only"), "Unknown retention")
        expected = set(LIMITS)
        if mode != "entire-original-container":
            expected.remove("original-container.mkv")
        require(set(os.listdir(directory)) == expected | {"manifest.json"}, "Package membership")
        integer(m["source_bytes"], 1)
        digest(m["source_sha256"])
        require(source_content == (m["source_bytes"], m["source_sha256"]), "Source content mismatch")
        integer(m["track_payload_original_offset"])
        for name in ("packets", "records"):
            integer(m[name], 1, COUNT_LIMIT)
        integer(m["enhancement_nals"], 0, COUNT_LIMIT * COUNT_LIMIT)
        require(type(m["components"]) is list and len(m["components"]) == len(expected), "Component count")
        components = {}
        for item in m["components"]:
            require(type(item) is dict and set(item) == {"name", "bytes", "sha256"}, "Component fields")
            name = item["name"]
            require(type(name) is str and name in expected and name not in components, "Component name")
            integer(item["bytes"], 1, LIMITS[name])
            digest(item["sha256"])
            fd = open_regular(name, LIMITS[name], directory, True)
            stack.callback(os.close, fd)
            before = identity(os.fstat(fd))
            actual = content(fd)
            require(actual == (item["bytes"], item["sha256"]), "Component content mismatch")
            components[name] = (fd, before, actual)
        track_offset, track, cfg, track_number = selected_track(source_fd)
        def bytes_of(name):
            fd, _, actual = components[name]
            return read_at(fd, 0, actual[0])
        require(track_offset == m["track_payload_original_offset"]
                and track == bytes_of("original-track-entry-payload.bin")
                and cfg == bytes_of("hevc-configuration.bin"), "Original track/configuration mismatch")
        if mode == "entire-original-container":
            require(components["original-container.mkv"][2] == source_content, "Original container mismatch")
        stored = rows(components["source-audit.jsonl"][0])
        refs = rows(components["rpu-index.jsonl"][0])
        archive_fd = components["original-rpu.bin"][0]
        offset = 0
        record_count = 0
        packet_count = 0
        complete = False
        resources = False
        begin = False
        try:
            with helper_rows(helper, source, timeout) as fresh:
                for row in fresh:
                    kind = row.get("kind")
                    require(not complete, "Rows after completion")
                    if kind == "resources":
                        require(not resources and begin and row.get("heap_limit") == 64 << 20,
                                "Helper resource receipt")
                        integer(row.get("peak_heap_bytes"), 1, 64 << 20)
                        resources = True
                        continue
                    require(not resources or kind == "complete", "Rows after resource receipt")
                    require(same_json(next(stored, None), row), "Stored audit differs from source")
                    if kind == "begin":
                        require(not begin and packet_count == 0 and record_count == 0
                                and row.get("version") == 3 and row.get("track_number") == track_number
                                and row.get("configuration_bytes") == len(cfg)
                                and row.get("configuration_sha256") == hashlib.sha256(cfg).hexdigest(), "Audit begin")
                        begin = True
                    elif kind == "packet":
                        require(begin and row.get("index") == packet_count, "Packet sequence")
                        packet_count += 1
                    elif kind == "rpu-summary":
                        require(begin and row.get("index") == record_count
                                and row.get("packet_index") == packet_count - 1, "RPU sequence")
                        size = integer(row.get("encoded_bytes"), 1, 65536)
                        source_offset = integer(row.get("input_byte_offset"))
                        expected_ref = dict(kind="original-rpu-reference", index=record_count,
                            packet_index=row["packet_index"], nal_index=row["nal_index"], pts_ns=row["pts_ns"],
                            original_payload_offset=source_offset, archive_delimiter_offset=offset,
                            payload_bytes=size, payload_sha256=row["sha256"])
                        require(same_json(next(refs, None), expected_ref), "RPU index differs from source")
                        original = read_at(source_fd, source_offset, size)
                        require(read_at(archive_fd, offset, size + 4) == b"\0\0\0\1" + original
                                and hashlib.sha256(original).hexdigest() == row["sha256"], "Original RPU bytes differ")
                        offset += size + 4
                        record_count += 1
                    elif kind == "complete":
                        require(begin and resources and row.get("version") == 3
                                and row.get("source_recheck") is True
                                and (row.get("input_bytes"), row.get("input_sha256")) == source_content
                                and row.get("packets") == packet_count == m["packets"]
                                and row.get("records") == record_count == m["records"]
                                and row.get("enhancement_nals") == m["enhancement_nals"], "Incomplete audit receipt")
                        complete = True
                    else:
                        raise Refused("Unknown audit row")
            require(complete and next(stored, None) is None and next(refs, None) is None
                    and offset == components["original-rpu.bin"][2][0], "Unconsumed component data")
        finally:
            stored.close()
            refs.close()
        require(content(source_fd) == source_content and identity(os.fstat(source_fd)) == source_before
                and identity(os.stat(source, follow_symlinks=False)) == source_before, "Source changed")
        for name, (fd, before, actual) in components.items():
            require(content(fd) == actual and identity(os.fstat(fd)) == before
                    and identity(os.stat(name, dir_fd=directory, follow_symlinks=False)) == before,
                    "Package component changed")
        require(content(manifest_fd) == manifest_content and identity(os.fstat(manifest_fd)) == manifest_before
                and identity(os.stat("manifest.json", dir_fd=directory, follow_symlinks=False)) == manifest_before,
                "Manifest changed")
        require(set(os.listdir(directory)) == expected | {"manifest.json"}
                and identity(os.fstat(directory)) == directory_before
                and identity(os.stat(package, follow_symlinks=False)) == directory_before, "Package changed")
        return dict(kind="development-original-companion-verification", retention=mode,
                    packets=packet_count, records=record_count, original_components_match_source=True,
                    source_identity_checked_at_boundaries=True, decoded_frame_association="not-established",
                    immutable_snapshot=False, stable_importer=False)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True)
    parser.add_argument("--package", required=True)
    parser.add_argument("--audit-helper", required=True)
    args = parser.parse_args()
    try:
        result = validate(args.source, args.package, args.audit_helper)
    except (Refused, OSError, ValueError):
        parser.exit(1, "Original companion verification refused; no package or source modified.\n")
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
