#!/usr/bin/env python3
"""Development-only whole-input base-frame/RPU association. No conversion admission."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import stat
import struct
import subprocess
import tempfile
import threading

LIMIT = 2_000_000
LINE_LIMIT = 65_536
I64 = 2**63 - 1


class Refusal(Exception):
    pass


def require(condition):
    if not condition:
        raise Refusal("Association contract not established")


def integer(row, key, lo=0, hi=I64):
    value = row.get(key)
    require(type(value) is int and lo <= value <= hi)
    return value


def sha(row, key):
    value = row.get(key)
    require(type(value) is str and len(value) == 64
            and all(c in "0123456789abcdef" for c in value))
    return value


def rows(stream):
    def unique_object(pairs):
        result = {}
        for key, value in pairs:
            require(key not in result)
            result[key] = value
        return result
    for _ in range(2 * LIMIT + 4):
        line = stream.readline(LINE_LIMIT + 1)
        if not line:
            return
        require(len(line) <= LINE_LIMIT and line.endswith(b"\n"))
        try:
            row = json.loads(line, object_pairs_hook=unique_object)
        except (ValueError, RecursionError, UnicodeError) as error:
            raise Refusal("Invalid bounded protocol") from error
        require(type(row) is dict)
        yield row
    raise Refusal("Protocol record bound exceeded")


def fingerprint(path):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as source:
        before = os.fstat(source.fileno())
        require(stat.S_ISREG(before.st_mode) and 0 < before.st_size <= 2**40)
        h = hashlib.sha256()
        while chunk := source.read(1024 * 1024):
            h.update(chunk)
        after = os.fstat(source.fileno())
    descriptor = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
    require(descriptor(before) == descriptor(after) == descriptor(os.stat(path, follow_symlinks=False)))
    return descriptor(before), h.hexdigest()


def spool(path):
    db = sqlite3.connect(path)
    db.execute("PRAGMA page_size=4096")
    db.execute("PRAGMA max_page_count=131072")  # 512 MiB, includes indices.
    db.execute("PRAGMA cache_size=-8192")
    db.execute("PRAGMA temp_store=FILE")
    db.execute("PRAGMA journal_mode=OFF")
    db.execute("CREATE TABLE packets (idx INTEGER PRIMARY KEY, pts INTEGER UNIQUE NOT NULL, "
               "pos INTEGER UNIQUE NOT NULL, size INTEGER NOT NULL, hash TEXT NOT NULL, "
               "rpu_size INTEGER, rpu_hash TEXT, packet_checked INTEGER NOT NULL DEFAULT 0, "
               "frame_checked INTEGER NOT NULL DEFAULT 0)")
    return db


def read_audit(db, stream, source_bytes, source_hash):
    header = None
    packets = records = 0
    resources = complete = False
    sequence = hashlib.sha256()
    for row in rows(stream):
        require(not complete)
        kind = row.get("kind")
        if header is None:
            require(kind == "begin" and integer(row, "version") == 3
                    and row.get("input_type") == "matroska-hevc-summary")
            integer(row, "configuration_bytes", 1, 1024 * 1024)
            sha(row, "configuration_sha256")
            header = row
        elif kind == "packet":
            require(not resources and packets < LIMIT and integer(row, "index") == packets)
            pts = integer(row, "pts_ns", -I64-1)
            pos = integer(row, "block_input_byte_offset", 0, source_bytes-1)
            payload_pos = integer(row, "input_byte_offset", pos+4, pos+11)
            size = integer(row, "encoded_bytes", 1, 16 * 1024 * 1024)
            require(payload_pos + size <= source_bytes)
            digest = sha(row, "sha256")
            # This contract deliberately refuses encoded invisibility/nonoutput declarations.
            require(row.get("invisible") is False)
            db.execute("INSERT INTO packets(idx,pts,pos,size,hash) VALUES(?,?,?,?,?)",
                       (packets, pts, pos, size, digest))
            sequence.update(struct.pack("<qq", pts, size) + bytes.fromhex(digest))
            packets += 1
        elif kind == "rpu-summary":
            require(not resources and records < LIMIT and integer(row, "index") == records
                    and integer(row, "packet_index") == packets-1)
            size, digest = integer(row, "encoded_bytes", 1, 65536), sha(row, "sha256")
            original = db.execute("SELECT pts,rpu_hash FROM packets WHERE idx=?", (packets-1,)).fetchone()
            require(original is not None and original[0] == integer(row, "pts_ns", -I64-1)
                    and original[1] is None)  # Never deduplicate surplus RPUs.
            db.execute("UPDATE packets SET rpu_size=?,rpu_hash=? WHERE idx=?", (size, digest, packets-1))
            records += 1
        elif kind == "resources":
            require(not resources and integer(row, "heap_limit") == 64 * 1024 * 1024
                    and integer(row, "peak_heap_bytes", 1, 64 * 1024 * 1024) > 0)
            resources = True
        elif kind == "complete":
            require(resources and integer(row, "version") == 3 and packets > 0
                    and integer(row, "packets") == packets == records == integer(row, "records")
                    and integer(row, "input_bytes") == source_bytes
                    and sha(row, "input_sha256") == source_hash
                    and sha(row, "packet_sequence_sha256") == sequence.hexdigest()
                    and row.get("source_recheck") is True)
            require(db.execute("SELECT COUNT(*) FROM packets WHERE rpu_hash IS NULL").fetchone()[0] == 0)
            complete = True
        else:
            raise Refusal("Unexpected audit record")
    require(complete and header is not None)
    db.commit()
    return header, packets


def ticks(row, key, time_base):
    value = integer(row, key, -I64-1)
    numerator = value * time_base[0] * 1_000_000_000
    result, remainder = divmod(numerator, time_base[1])
    require(remainder == 0 and -I64-1 <= result <= I64)
    return result


def geometry(row):
    width, height = integer(row, "width", 1, 8192), integer(row, "height", 1, 8192)
    require(width * height <= 4096 * 4096 and row.get("interlaced") is False
            and row.get("pixel_format") == "yuv420p10le")
    crop = row.get("codec_crop_left_right_top_bottom")
    sar = row.get("sample_aspect_ratio")
    require(type(crop) is list and len(crop) == 4
            and all(type(v) is int and 0 <= v <= 8191 for v in crop)
            and crop[0] + crop[1] < width and crop[2] + crop[3] < height)
    require(type(sar) is list and len(sar) == 2 and all(type(v) is int and 1 <= v <= 65535 for v in sar))
    return (width, height, row["pixel_format"], tuple(crop), tuple(sar))


def read_reference(db, stream, audit, expected, source_bytes, threads=4):
    header = None
    packets = frames = 0
    complete = False
    picture_geometry = None
    previous_pts = None
    for row in rows(stream):
        require(not complete)
        kind = row.get("kind")
        if header is None:
            require(kind == "begin" and integer(row, "version") == 1
                    and integer(row, "input_bytes") == source_bytes
                    and integer(row, "configuration_bytes") == audit["configuration_bytes"]
                    and sha(row, "configuration_sha256") == audit["configuration_sha256"]
                    and row.get("decoder") == "hevc" and row.get("automatic_codec_crop") is False
                    and integer(row, "threads") == threads)
            time_base = row.get("time_base")
            require(type(time_base) is list and len(time_base) == 2
                    and all(type(v) is int and 1 <= v <= 2**31-1 for v in time_base))
            header = row
        elif kind == "packet":
            require(packets < expected and integer(row, "index") == packets)
            observed = (ticks(row, "pts", time_base), integer(row, "block_input_byte_offset"),
                        integer(row, "encoded_bytes"), sha(row, "sha256"))
            original = db.execute("SELECT pts,pos,size,hash FROM packets WHERE idx=?", (packets,)).fetchone()
            require(observed == original)
            db.execute("UPDATE packets SET packet_checked=1 WHERE idx=?", (packets,))
            packets += 1
        elif kind == "frame":
            require(frames < expected and integer(row, "index") == frames)
            idx = integer(row, "packet_index", 0, packets-1)
            pts = ticks(row, "pts", time_base)
            require(pts == ticks(row, "packet_pts", time_base) == ticks(row, "best_effort_pts", time_base)
                    and (previous_pts is None or pts > previous_pts))
            observed = (pts, integer(row, "block_input_byte_offset"), integer(row, "packet_size"),
                        integer(row, "rpu_bytes", 1, 65536), sha(row, "rpu_sha256"), 1, 0)
            original = db.execute("SELECT pts,pos,size,rpu_size,rpu_hash,packet_checked,frame_checked "
                                  "FROM packets WHERE idx=?", (idx,)).fetchone()
            require(observed == original)
            current = geometry(row)
            require(picture_geometry is None or current == picture_geometry)
            picture_geometry = current
            previous_pts = pts
            db.execute("UPDATE packets SET frame_checked=1 WHERE idx=?", (idx,))
            frames += 1
        elif kind == "complete":
            require(integer(row, "version") == 1 and integer(row, "packets") == packets == expected
                    and integer(row, "frames") == frames == expected and row.get("decoder_drained") is True
                    and row.get("descriptor_unchanged") is True)
            require(db.execute("SELECT COUNT(*) FROM packets WHERE packet_checked!=1 OR frame_checked!=1")
                    .fetchone()[0] == 0)
            complete = True
        else:
            raise Refusal("Unexpected decoder record")
    require(complete and picture_geometry is not None)
    db.commit()
    return {"packets": packets, "frames": frames, "geometry": picture_geometry,
            "codec_visible_size": [picture_geometry[0]-sum(picture_geometry[3][:2]),
                                   picture_geometry[1]-sum(picture_geometry[3][2:])],
            "scope": "decoded-base-frame/raw-RPU agreement only; no EL, edits or rendering qualification"}


def consume(command, reader):
    """Require EOF plus exit zero; bounded stdout, silent private errors, owned child join."""
    child = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    timed_out = threading.Event()
    def timeout():
        timed_out.set()
        child.kill()
    timer = threading.Timer(7200, timeout)
    timer.start()
    try:
        result = reader(child.stdout)
        require(child.wait() == 0 and not timed_out.is_set())
        return result
    finally:
        timer.cancel()
        if child.poll() is None:
            child.kill()
        child.wait()
        child.stdout.close()
        timer.join()


def check(source, audit_executable, reference_executable, threads=4):
    require(threads in (1, 4))
    initial, source_hash = fingerprint(source)
    with tempfile.TemporaryDirectory(prefix="staxrip-frame-association-") as directory:
        db = spool(Path(directory) / "associations.sqlite")
        try:
            audit, count = consume([str(audit_executable), "mkv-summary", str(source)],
                lambda stream: read_audit(db, stream, initial[2], source_hash))
            result = consume([str(reference_executable), str(source), "--threads", str(threads)],
                lambda stream: read_reference(db, stream, audit, count, initial[2], threads))
            require(fingerprint(source) == (initial, source_hash))
            result["spool_bytes"] = db.execute("PRAGMA page_count").fetchone()[0] * 4096
            return result
        finally:
            db.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--audit", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--threads", type=int, choices=(1, 4), default=4)
    args = parser.parse_args()
    try:
        print(json.dumps(check(args.source, args.audit.resolve(), args.reference.resolve(), args.threads)))
    except (Refusal, OSError, sqlite3.Error, KeyboardInterrupt):
        parser.exit(1, "Whole-input frame association not established.\n")
