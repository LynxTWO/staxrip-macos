"""Actual generated HEVC integration plus association/protocol refusal tests."""
import copy
import io
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import check

ROOT = Path(__file__).resolve().parents[2]
AUDIT = ROOT / "Tools/DolbyMetadataAudit/target/release/staxrip-dolby-metadata-audit"


def wire(rows):
    return io.BytesIO(b"".join(json.dumps(row).encode() + b"\n" for row in rows))


class ReferenceTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="staxrip-reference-test-")
        cls.addClassCleanup(cls.directory.cleanup)
        cls.path = Path(cls.directory.name)
        environment = dict(os.environ, STAXRIP_GENERATED_DOLBY_REFERENCE_DIRECTORY=str(cls.path))
        subprocess.run(["cargo", "test", "--locked", "--manifest-path",
            str(ROOT / "Tools/DolbyMetadataAudit/Cargo.toml"),
            "actual_hevc_packets_and_rpu_association_match_independent_ffprobe"],
            env=environment, check=True, stdout=subprocess.DEVNULL)
        subprocess.run(["cargo", "build", "--release", "--locked", "--manifest-path",
            str(ROOT / "Tools/DolbyMetadataAudit/Cargo.toml")], check=True, stdout=subprocess.DEVNULL)
        cls.reference = cls.path / "reference"
        subprocess.run([sys.executable, str(Path(__file__).with_name("build.py")),
                        "--output", str(cls.reference)], check=True)
        cls.source = cls.path / "single.mkv"
        cls.fingerprint, cls.hash = check.fingerprint(cls.source)
        cls.audit_rows = [json.loads(line) for line in subprocess.check_output(
            [str(AUDIT), "mkv-summary", str(cls.source)]).splitlines()]
        cls.reference_rows = [json.loads(line) for line in subprocess.check_output(
            [str(cls.reference), str(cls.source)]).splitlines()]

    def database(self):
        directory = tempfile.TemporaryDirectory(dir=self.path)
        self.addCleanup(directory.cleanup)
        db = check.spool(Path(directory.name) / "spool.sqlite")
        self.addCleanup(db.close)
        return db

    def validate(self, audit=None, reference=None):
        db = self.database()
        header, count = check.read_audit(db, wire(audit if audit is not None else self.audit_rows),
                                        self.fingerprint[2], self.hash)
        return check.read_reference(db, wire(reference if reference is not None else self.reference_rows),
                                    header, count, self.fingerprint[2])

    def test_actual_b_frames_groups_and_variable_vint(self):
        for case in ("single", "group", "wide-vint"):
            for threads in (1, 4):
                with self.subTest(case=case, threads=threads):
                    result = check.check(self.path / (case + ".mkv"), AUDIT, self.reference, threads)
                    self.assertEqual((result["packets"], result["frames"]), (4, 4))
                    self.assertEqual(result["geometry"][:3], (160, 96, "yuv420p10le"))
                    self.assertLessEqual(result["spool_bytes"], 512 * 1024 * 1024)
        packets = [r["pts"] for r in self.reference_rows if r["kind"] == "packet"]
        frames = [r["packet_index"] for r in self.reference_rows if r["kind"] == "frame"]
        self.assertEqual(packets, [0, 120, 80, 40])
        self.assertEqual(frames, [0, 3, 2, 1])
        self.assertEqual(len({r["rpu_sha256"] for r in self.reference_rows if r["kind"] == "frame"}), 4)

    def test_actual_surplus_missing_and_unusable_timing_refuse(self):
        for case in ("duplicate", "missing", "negative", "duplicate-pts"):
            with self.subTest(case=case), self.assertRaises((check.Refusal, sqlite3.Error)):
                check.check(self.path / (case + ".mkv"), AUDIT, self.reference)

    def test_actual_codec_conformance_crop_is_distinct_from_container_crop(self):
        source = self.path / "conformance.mkv"
        result = check.check(source, AUDIT, self.reference)
        self.assertEqual(result["geometry"], (176, 112, "yuv420p10le", (0, 14, 0, 14), (1, 1)))
        self.assertEqual(result["codec_visible_size"], [162, 98])
        audit = json.loads(subprocess.check_output([str(AUDIT), "mkv-summary", str(source)]).splitlines()[0])
        self.assertEqual([audit["declared_pixel_width"], audit["declared_pixel_height"]], [162, 98])
        self.assertEqual(audit["declared_crop_left_right_top_bottom"], [0, 0, 1, 0])
        self.assertEqual(audit["declared_display_unit"], 3)
        self.assertEqual(audit["declared_display_width_height"], [16, 9])
        normal = subprocess.check_output(["ffprobe", "-v", "error", "-select_streams", "v:0",
            "-show_frames", "-show_entries", "frame=width,height:frame_side_data=:"
            "frame_side_data_component=:frame_side_data_piece=", "-of", "compact", str(source)], text=True)
        self.assertEqual(normal.count("width=162|height=98"), 4)

    def test_actual_cra_nonoutput_prefix_refuses_without_dropping_metadata(self):
        intact = check.check(self.path / "whole-gop.mkv", AUDIT, self.reference)
        self.assertEqual((intact["packets"], intact["frames"]), (24, 24))
        source = self.path / "cra-start.mkv"
        reference = [json.loads(line) for line in subprocess.check_output(
            [str(self.reference), str(source)]).splitlines()]
        receipt = reference[-1]
        self.assertEqual(receipt["kind"], "complete")
        self.assertLess(receipt["frames"], receipt["packets"])
        with self.assertRaises(check.Refusal):
            check.check(source, AUDIT, self.reference)

    def test_reference_mutations_refuse(self):
        mutations = [
            ("begin", "configuration_sha256", "0" * 64),
            ("begin", "time_base", [1, 1001]),
            ("begin", "automatic_codec_crop", True),
            ("begin", "threads", 2),
            ("packet", "sha256", "0" * 64),
            ("packet", "block_input_byte_offset", 1),
            ("packet", "encoded_bytes", 1),
            ("frame", "packet_index", 1),
            ("frame", "packet_pts", 1),
            ("frame", "best_effort_pts", 1),
            ("frame", "rpu_sha256", "0" * 64),
            ("frame", "rpu_bytes", 1),
            ("frame", "interlaced", True),
            ("frame", "pixel_format", "yuv420p"),
            ("frame", "codec_crop_left_right_top_bottom", [0, 0, 96, 0]),
            ("frame", "sample_aspect_ratio", [1, 0]),
            ("complete", "frames", 3),
            ("complete", "decoder_drained", False),
            ("complete", "descriptor_unchanged", False),
        ]
        for kind, key, value in mutations:
            with self.subTest(kind=kind, key=key):
                rows = copy.deepcopy(self.reference_rows)
                next(row for row in rows if row["kind"] == kind)[key] = value
                with self.assertRaises(check.Refusal):
                    self.validate(reference=rows)
        for key, value in (("width", 162), ("sample_aspect_ratio", [2, 1]),
                           ("codec_crop_left_right_top_bottom", [0, 0, 1, 0])):
            rows = copy.deepcopy(self.reference_rows)
            [r for r in rows if r["kind"] == "frame"][1][key] = value
            with self.subTest(changing_geometry=key), self.assertRaises(check.Refusal):
                self.validate(reference=rows)

    def test_audit_mutations_refuse(self):
        for kind, key, value in (
            ("packet", "pts_ns", True), ("packet", "invisible", True),
            ("rpu-summary", "pts_ns", 1), ("rpu-summary", "packet_index", 3),
            ("complete", "input_sha256", "0" * 64),
            ("complete", "packet_sequence_sha256", "0" * 64),
            ("complete", "records", 3), ("complete", "source_recheck", False),
            ("resources", "heap_limit", 1),
        ):
            with self.subTest(kind=kind, key=key):
                rows = copy.deepcopy(self.audit_rows)
                next(row for row in rows if row["kind"] == kind)[key] = value
                with self.assertRaises(check.Refusal):
                    self.validate(audit=rows)

    def test_missing_duplicate_reordered_and_trailing_records_refuse(self):
        for is_audit in (True, False):
            original = self.audit_rows if is_audit else self.reference_rows
            frame_or_rpu = next(i for i, r in enumerate(original) if r["kind"] in ("frame", "rpu-summary"))
            variants = [original[:-1], original + [original[-1]],
                        original[:frame_or_rpu] + original[frame_or_rpu+1:],
                        original[:frame_or_rpu] + [original[frame_or_rpu]] + original[frame_or_rpu:],
                        original[:1] + list(reversed(original[1:-1])) + original[-1:]]
            for index, rows in enumerate(variants):
                with self.subTest(audit=is_audit, variant=index), self.assertRaises(check.Refusal):
                    self.validate(**({"audit": rows} if is_audit else {"reference": rows}))

    def test_bounded_lines_and_duplicate_json_keys_refuse(self):
        for data in (b"{}", b"[]\n", b"{" + b"x" * check.LINE_LIMIT + b"}\n",
                     b'{"kind":"begin","kind":"complete"}\n', b'{"a":{"x":1,"x":2}}\n'):
            with self.subTest(data_length=len(data)), self.assertRaises(check.Refusal):
                list(check.rows(io.BytesIO(data)))

    def test_receipt_requires_zero_exit(self):
        with self.assertRaises(check.Refusal):
            check.consume([sys.executable, "-c", "print('{}'); raise SystemExit(1)"],
                          lambda stream: list(check.rows(stream)))

    def test_interrupted_reader_settles_owned_child_and_pipe(self):
        children = []
        real_popen = subprocess.Popen
        def started(*args, **kwargs):
            child = real_popen(*args, **kwargs)
            children.append(child)
            return child
        def interrupted(stream):
            raise KeyboardInterrupt()
        with patch.object(check.subprocess, "Popen", started), self.assertRaises(KeyboardInterrupt):
            check.consume([sys.executable, "-c", "import time; time.sleep(30)"], interrupted)
        self.assertEqual(len(children), 1)
        self.assertIsNotNone(children[0].poll())
        self.assertTrue(children[0].stdout.closed)

    def test_sqlite_page_limit_refuses_real_growth(self):
        db = self.database()
        # Exercise SQLite's actual resource failure at a small cap, not a mocked return.
        db.execute("PRAGMA max_page_count=8")
        with self.assertRaises(sqlite3.OperationalError) as failure:
            for index in range(10_000):
                db.execute("INSERT INTO packets(idx,pts,pos,size,hash,rpu_size,rpu_hash) VALUES(?,?,?,?,?,?,?)",
                           (index, index, index, 1, "0" * 64, 1, "0" * 64))
        self.assertEqual(failure.exception.sqlite_errorcode, sqlite3.SQLITE_FULL)

    def test_builder_refuses_existing_and_dangling_symlink_destinations(self):
        existing = self.path / "existing-output"
        existing.write_bytes(b"protected")
        dangling = self.path / "dangling-output"
        dangling.symlink_to(self.path / "absent-target")
        for destination in (existing, dangling):
            result = subprocess.run([sys.executable, str(Path(__file__).with_name("build.py")),
                "--output", str(destination)], capture_output=True, timeout=2)
            self.assertNotEqual(result.returncode, 0)
        self.assertEqual(existing.read_bytes(), b"protected")
        self.assertTrue(dangling.is_symlink())
        self.assertFalse((self.path / "absent-target").exists())

    def test_builder_sets_native_deployment_target_and_rejects_unsupported_target(self):
        # Inspect the real Mach-O; a compiler flag alone does not prove its result.
        build = subprocess.check_output(["vtool", "-show-build", str(self.reference)], text=True)
        self.assertRegex(build, r"minos\s+14\.0(?:\s|$)")
        destination = self.path / "unsupported-target"
        result = subprocess.run([sys.executable, str(Path(__file__).with_name("build.py")),
            "--output", str(destination), "--deployment-target", "27.0"], capture_output=True, timeout=2)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(destination.exists())

    def test_final_source_change_refuses_and_restores_generated_file(self):
        original = self.source.read_bytes()
        real_consume = check.consume
        count = 0
        def consumed(command, reader):
            nonlocal count
            result = real_consume(command, reader)
            count += 1
            if count == 2:
                self.source.write_bytes(original + b"changed-generated-input")
            return result
        try:
            with patch.object(check, "consume", consumed), self.assertRaises(check.Refusal):
                check.check(self.source, AUDIT, self.reference)
        finally:
            self.source.write_bytes(original)

    def test_nonregular_input_refuses_promptly(self):
        fifo = self.path / "generated-fifo"
        os.mkfifo(fifo)
        result = subprocess.run([str(self.reference), str(fifo)], capture_output=True, timeout=2)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, b"")
        self.assertNotIn(str(fifo).encode(), result.stderr)


if __name__ == "__main__":
    unittest.main()
