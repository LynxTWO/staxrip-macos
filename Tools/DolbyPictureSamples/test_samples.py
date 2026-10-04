"""Generated sample/stride/crop checks; CLI oracle is test-only and shares FFmpeg."""
import hashlib
import json
import os
from pathlib import Path
import select
import shlex
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import time
import unittest

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


class OwnedPipe:
    """Sole test owner, finite read deadline and joined direct child, no runtime bridge."""
    def __init__(self, command, directory, seconds=30):
        self.log = tempfile.TemporaryFile(dir=directory)
        self.child = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=self.log, start_new_session=True)
        os.set_blocking(self.child.stdout.fileno(), False)
        self.deadline = time.monotonic() + seconds

    def read(self, count):
        while True:
            left = self.deadline - time.monotonic()
            if left <= 0:
                raise TimeoutError("Owned generated sample child deadline")
            if select.select([self.child.stdout], [], [], min(left, 0.1))[0]:
                try:
                    return os.read(self.child.stdout.fileno(), count)
                except BlockingIOError:
                    pass

    def exact(self, count):
        result = bytearray()
        while len(result) < count:
            data = self.read(count - len(result))
            if not data:
                raise AssertionError("Short generated raw sample row")
            result.extend(data)
        return bytes(result)

    def finish(self):
        code = self.child.wait(timeout=max(0.01, self.deadline - time.monotonic()))
        self.child.stdout.close()
        size = self.log.tell()
        self.log.seek(0)
        error = self.log.read(1024 * 1024 + 1)
        self.log.close()
        if size > 1024 * 1024:
            raise AssertionError("Generated diagnostic bound")
        return code, error

    def abort(self):
        # PID is not reaped before signal, so a completed direct child remains reserved.
        try:
            os.killpg(self.child.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            self.child.wait(timeout=2)
        except subprocess.TimeoutExpired:
            os.killpg(self.child.pid, signal.SIGKILL)
            self.child.wait(timeout=5)
        self.child.stdout.close()
        self.log.close()


def bounded(command, directory, limit=1024 * 1024, seconds=30):
    owner = OwnedPipe(command, directory, seconds)
    try:
        output = bytearray()
        while True:
            data = owner.read(min(16384, limit + 1 - len(output)))
            if not data:
                break
            output.extend(data)
            if len(output) > limit:
                raise AssertionError("Generated output bound")
        code, error = owner.finish()
        return code, bytes(output), error
    except BaseException:
        if not owner.child.stdout.closed:
            owner.abort()
        raise


def expected(values, width, height):
    data = b"".join(struct.pack("<H", v) for v in values)
    return dict(width=width, height=height, samples=len(values), minimum=min(values),
        maximum=max(values), sum=sum(values), sum_squares=sum(v*v for v in values),
        sha256=hashlib.sha256(data).hexdigest())


def identity(path):
    s = path.stat()
    return (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns, s.st_mode, s.st_nlink)


class SampleTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.path = Path(tempfile.mkdtemp(prefix="staxrip-generated-samples-"))
        cls.addClassCleanup(shutil.rmtree, cls.path)
        # Independent target ownership: never remove/rebuild another fixture's artifact.
        environment = dict(os.environ, STAXRIP_GENERATED_DOLBY_REFERENCE_DIRECTORY=str(cls.path),
            CARGO_TARGET_DIR=str(ROOT / "Tools/DolbyMetadataAudit/target/owned-PictureSampleTests"))
        with (cls.path / "generated-build.log").open("xb") as log:
            subprocess.run(["cargo", "test", "--locked", "--manifest-path",
                str(ROOT / "Tools/DolbyMetadataAudit/Cargo.toml"),
                "actual_hevc_packets_and_rpu_association_match_independent_ffprobe"],
                env=environment, check=True, stdout=log, stderr=log, timeout=120)
        cls.probe = cls.path / "sample-probe"
        subprocess.run([sys.executable, str(HERE / "build.py"), "--output", str(cls.probe)],
            check=True, timeout=80)
        flags = shlex.split(subprocess.check_output(["pkg-config", "--cflags", "--libs",
            "libavcodec", "libavformat", "libavutil"], text=True, timeout=10))
        cls.planes = cls.path / "sanitized-planes"
        subprocess.run(["clang", "-std=c11", "-Wall", "-Wextra", "-Werror",
            "-fsanitize=address,undefined", "-fno-omit-frame-pointer", str(HERE / "test_planes.c"),
            "-o", str(cls.planes), *flags], check=True, timeout=60)

    def probe_rows(self, source, threads):
        code, output, error = bounded([str(self.probe), str(source), "--threads", str(threads)], self.path)
        self.assertEqual(code, 0, error)
        self.assertTrue(output.endswith(b"\n"))
        self.assertTrue(all(len(line) < 65536 for line in output.splitlines()))
        rows = [json.loads(line) for line in output.splitlines()]
        self.assertEqual(rows[0]["kind"], "sample-begin")
        self.assertEqual(rows[-1]["kind"], "sample-complete")
        self.assertTrue(rows[-1]["decoder_drained"])
        return rows

    def oracle(self, source, frames, visible):
        # Decode rows only; no full picture or raw pixel payload retained in the parent.
        command = ["ffmpeg", "-v", "error", "-threads", "1", "-apply_cropping", "0",
            "-i", str(source), "-map", "0:v:0"]
        if visible:
            # CLI default also applies container cropping. Select just the explicit
            # codec rectangle, with exact chroma-aligned crop and no resize filter.
            f = frames[0]; left, right, top, bottom = f["codec_crop_left_right_top_bottom"]
            command += ["-vf", f"crop={f['width']-left-right}:{f['height']-top-bottom}:{left}:{top}:exact=1"]
        command += ["-fps_mode", "passthrough", "-pix_fmt", "yuv420p10le", "-f", "rawvideo", "pipe:1"]
        owner = OwnedPipe(command, self.path)
        try:
            for frame in frames:
                crop = frame["codec_crop_left_right_top_bottom"]
                width = frame["width"] - (crop[0] + crop[1] if visible else 0)
                height = frame["height"] - (crop[2] + crop[3] if visible else 0)
                for i, reported in enumerate(frame["codec_visible" if visible else "coded"]):
                    w, h = width >> bool(i), height >> bool(i)
                    sha = hashlib.sha256()
                    total = squares = count = 0
                    low, high = 1023, 0
                    for _ in range(h):
                        row = owner.exact(w * 2)
                        sha.update(row)
                        for (value,) in struct.iter_unpack("<H", row):
                            self.assertLessEqual(value, 1023)
                            low, high = min(low, value), max(high, value)
                            total += value; squares += value*value; count += 1
                    self.assertEqual(reported, dict(width=w, height=h, samples=count,
                        minimum=low, maximum=high, sum=total, sum_squares=squares, sha256=sha.hexdigest()))
            self.assertEqual(owner.read(1), b"")
            code, error = owner.finish()
            self.assertEqual(code, 0, error)
        except BaseException:
            if not owner.child.stdout.closed:
                owner.abort()
            raise

    def test_actual_coded_and_visible_samples_both_thread_choices(self):
        for case in ("single", "group", "wide-vint", "conformance", "whole-gop"):
            source = self.path / (case + ".mkv")
            before = (identity(source), hashlib.sha256(source.read_bytes()).digest())
            for threads in (1, 4):
                with self.subTest(case=case, threads=threads):
                    rows = self.probe_rows(source, threads)
                    frames = [row for row in rows if row["kind"] == "sample-frame"]
                    count = 24 if case == "whole-gop" else 4
                    self.assertEqual((len(frames), rows[-1]["frames"], rows[-1]["packets"]), (count, count, count))
                    for frame in frames:
                        self.assertFalse(frame["container_crop_applied"])
                        self.assertFalse(frame["edited_picture_semantics_verified"])
                        self.assertEqual(frame["sample_encoding"], "little-endian-uint16-code-values")
                    if case == "conformance":
                        self.assertEqual((frames[0]["width"], frames[0]["height"]), (176,112))
                        self.assertEqual(frames[0]["codec_crop_left_right_top_bottom"], [0,14,0,14])
                        self.assertEqual((frames[0]["codec_visible"][0]["width"], frames[0]["codec_visible"][0]["height"]), (162,98))
                        self.assertNotEqual(frames[0]["coded"][0]["sha256"], frames[0]["codec_visible"][0]["sha256"])
                    else:
                        self.assertEqual(frames[0]["coded"], frames[0]["codec_visible"])
                    self.oracle(source, frames, False)
                    self.oracle(source, frames, True)
            self.assertEqual(identity(source), before[0])
            self.assertEqual(hashlib.sha256(source.read_bytes()).digest(), before[1])

    def test_sanitized_stride_unaligned_roi_bounds_and_maximum_plane(self):
        code, output, error = bounded([str(self.planes)], self.path)
        self.assertEqual(code, 0, error)
        rows = [json.loads(line) for line in output.splitlines()]
        roi = expected([512,6,9,10], 2, 2); roi.pop("width"); roi.pop("height")
        full = expected([0,1,1023,3,4,512,6,7,8,9,10,11], 4, 3); full.pop("width"); full.pop("height")
        self.assertEqual(rows[:2], [roi, full])
        count = 4096 * 4096
        sha = hashlib.sha256()
        for _ in range(4096):
            sha.update(b"\xff\x03" * 4096)
        self.assertEqual(rows[2], dict(samples=count, sum=count*1023, sum_squares=count*1023*1023,
            minimum=1023, maximum=1023, sha256=sha.hexdigest()))

    def test_invalid_inputs_and_broken_output_are_not_complete(self):
        fifo = self.path / "sample-fifo"; os.mkfifo(fifo)
        alias = self.path / "sample-alias"; alias.symlink_to(self.path / "single.mkv")
        malformed = self.path / "sample-malformed"; malformed.write_bytes(b"not matroska")
        for command in ([str(self.probe)], [str(self.probe), str(fifo)], [str(self.probe), str(alias)],
            [str(self.probe), str(malformed)], [str(self.probe), str(self.path / "single.mkv"), "--threads", "2"]):
            code, output, error = bounded(command, self.path, seconds=2)
            self.assertNotEqual(code, 0)
            self.assertNotIn(b'"kind":"sample-complete"', output)
            self.assertNotIn(str(self.path).encode(), error)
        child = subprocess.Popen([str(self.probe), str(self.path / "whole-gop.mkv")],
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, start_new_session=True)
        child.stdout.close()
        self.assertGreater(child.wait(timeout=5), 0)  # SIGPIPE ignored; ordinary refusal, no crash.

    def test_active_cancellation_and_source_substitution_settle_without_receipt(self):
        original = (self.path / "single.mkv").read_bytes()
        segment = original.index(bytes.fromhex("18538067")) + 4
        width = next(i for i in range(1, 9) if original[segment] & (1 << (8-i)))
        cluster = original.index(bytes.fromhex("1f43b675"), segment + width)
        repeated = bytearray(original[:cluster])
        repeated[segment:segment+width] = bytes([255 >> (width-1)]) + b"\xff" * (width-1)
        repeated += original[cluster:] * 2000
        for kind in ("cancel", "substitute"):
            source = self.path / ("live-" + kind + ".mkv")
            source.write_bytes(repeated)
            fingerprint = hashlib.sha256(repeated).digest()
            owner = OwnedPipe([str(self.probe), str(source), "--threads", "1"], self.path)
            try:
                prefix = bytearray()
                while b'"kind":"sample-frame"' not in prefix:
                    data = owner.read(16384)
                    self.assertTrue(data)
                    prefix.extend(data)
                    self.assertLess(len(prefix), 65536)
                # Acknowledged actual sample production, with direct child still live.
                state = subprocess.check_output(["ps", "-p", str(owner.child.pid), "-o", "stat="], text=True)
                self.assertTrue(state.strip())
                self.assertNotIn("Z", state)
                if kind == "cancel":
                    owner.abort()
                    self.assertEqual(owner.child.returncode, -signal.SIGTERM)
                else:
                    held = source.with_suffix(".held")
                    source.rename(held)
                    source.write_bytes(repeated)
                    tail = b""
                    total = 0
                    while True:
                        data = owner.read(16384)
                        if not data:
                            break
                        total += len(data)
                        self.assertLess(total, 64 * 1024 * 1024)
                        self.assertNotIn(b'"kind":"sample-complete"', tail + data)
                        tail = data[-64:]
                    code, _ = owner.finish()
                    self.assertGreater(code, 0)
                    self.assertEqual(hashlib.sha256(held.read_bytes()).digest(), fingerprint)
                self.assertEqual(hashlib.sha256(source.read_bytes()).digest(), fingerprint)
            except BaseException:
                if not owner.child.stdout.closed:
                    owner.abort()
                raise

    def test_builder_never_replaces_existing_or_symlink_output(self):
        for output in (self.probe, self.path / "dangling-output"):
            if output != self.probe:
                output.symlink_to(self.path / "absent")
            before = output.lstat()
            code, _, _ = bounded([sys.executable, str(HERE / "build.py"), "--output", str(output)], self.path)
            self.assertNotEqual(code, 0)
            self.assertEqual(output.lstat(), before)
        code, _, _ = bounded([sys.executable, str(HERE / "build.py"), "--output", str(self.path / "never-created"),
            "--deployment-target", "13.0"], self.path)
        self.assertNotEqual(code, 0)
        self.assertFalse((self.path / "never-created").exists())


if __name__ == "__main__":
    unittest.main()
