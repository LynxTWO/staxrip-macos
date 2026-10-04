"""Generated actual packages, semantic forgery and owned helper refusal checks."""
import contextlib
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

import check

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "Tools/DolbyMetadataAudit/target/release/staxrip-dolby-metadata-audit"


def write_rows(path, rows):
    path.write_bytes(b"".join(json.dumps(row).encode() + b"\n" for row in rows))


def read_rows(path):
    return [json.loads(line) for line in path.read_bytes().splitlines()]


class CompanionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix="staxrip-companion-generated-")
        cls.addClassCleanup(cls.directory.cleanup)
        cls.root = Path(cls.directory.name)
        environment = dict(os.environ, STAXRIP_GENERATED_COMPANION_FIXTURE_DIRECTORY=str(cls.root))
        subprocess.run(["cargo", "test", "--locked", "--manifest-path",
                        str(ROOT / "Tools/DolbyMetadataAudit/Cargo.toml"),
                        "original_companions_preserve_raw_bytes_encoded_order_and_distinct_retention"],
                       env=environment, check=True, stdout=subprocess.DEVNULL)
        subprocess.run(["cargo", "build", "--release", "--locked", "--manifest-path",
                        str(ROOT / "Tools/DolbyMetadataAudit/Cargo.toml")], check=True,
                       stdout=subprocess.DEVNULL)

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(dir=self.root)
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name)
        self.source = self.path / "source.mkv"
        shutil.copyfile(self.root / "generated-source.mkv", self.source)
        self.package = self.path / "package"
        shutil.copytree(self.root / "metadata", self.package)

    def reset(self, mode="metadata"):
        shutil.rmtree(self.package)
        shutil.copytree(self.root / mode, self.package)

    def validate(self, helper=HELPER, timeout=120):
        return check.validate(self.source, self.package, helper, timeout=timeout)

    def refuse(self, helper=HELPER, timeout=120):
        started = []
        real = subprocess.Popen
        def tracked(*args, **kwargs):
            child = real(*args, **kwargs)
            started.append(child)
            return child
        with patch.object(check.subprocess, "Popen", tracked):
            with self.assertRaises((check.Refused, OSError)):
                self.validate(helper, timeout)
        for child in started:
            self.assertIsNotNone(child.returncode, "Refusal must join every owned direct child")
            self.assertTrue(child.stdout.closed, "Refusal must close every owned stdout pipe")

    def manifest(self, change):
        path = self.package / "manifest.json"
        m = json.loads(path.read_bytes())
        change(m)
        path.write_text(json.dumps(m) + "\n")

    def repair(self, name):
        data = (self.package / name).read_bytes()
        def fix(m):
            item = next(c for c in m["components"] if c["name"] == name)
            item.update(bytes=len(data), sha256=hashlib.sha256(data).hexdigest())
        self.manifest(fix)

    def test_both_modes_retain_duplicate_signed_unsorted_encoded_associations(self):
        original = self.source.read_bytes()
        for mode in ("metadata", "full"):
            with self.subTest(mode=mode):
                self.reset(mode)
                before = {p.name: p.read_bytes() for p in self.package.iterdir()}
                result = self.validate()
                self.assertEqual((result["packets"], result["records"]), (4, 5))
                self.assertEqual(result["source_file_id"], [self.source.stat().st_dev, self.source.stat().st_ino])
                self.assertEqual(result["stage_file_id"], [self.package.stat().st_dev, self.package.stat().st_ino])
                self.assertEqual(result["source_bytes"], len(original))
                self.assertEqual(result["source_sha256"], hashlib.sha256(original).hexdigest())
                self.assertEqual({m["name"]: (m["bytes"], m["sha256"]) for m in result["components"]},
                                 {name: (len(data), hashlib.sha256(data).hexdigest()) for name, data in before.items()})
                self.assertTrue(result["source_identity_checked_at_boundaries"])
                self.assertEqual(result["decoded_frame_association"], "not-established")
                self.assertFalse(result["immutable_snapshot"] or result["stable_importer"])
                refs = read_rows(self.package / "rpu-index.jsonl")
                self.assertEqual([r["pts_ns"] for r in refs],
                                 [-10000000, -10000000, 40000000, 5000000, 40000000])
                self.assertEqual(refs[0]["payload_sha256"], refs[1]["payload_sha256"])
                self.assertEqual(before, {p.name: p.read_bytes() for p in self.package.iterdir()})
                self.assertFalse(json.loads(before["manifest.json"])["source_path_identity_bound"])
        self.assertEqual(self.source.read_bytes(), original)

    def test_component_hash_corruption_and_missing_extra_members(self):
        for name in check.LIMITS:
            with self.subTest(name=name):
                self.reset("full")
                path = self.package / name
                data = bytearray(path.read_bytes())
                data[-1] ^= 1
                path.write_bytes(data)
                self.refuse()
                self.reset("full")
                (self.package / name).unlink()
                self.refuse()
        self.reset()
        (self.package / "extra").write_bytes(b"extra")
        self.refuse()

    def test_manifest_bounds_flags_unknown_fields_names_and_versions(self):
        changes = [("version", 1), ("version", False), ("records", 0), ("records", True),
                   ("records", 6), ("packets", 5), ("enhancement_nals", 0),
                   ("packets", check.COUNT_LIMIT + 1), ("source_bytes", -1),
                   ("source_sha256", "0" * 64), ("track_payload_original_offset", 0),
                   ("source_path_identity_bound", True), ("decoded_frame_association", "qualified"),
                   ("metadata_rewritten", True), ("source_content_recheck", 1),
                   ("retention", "selected-video-only"), ("unknown", 1)]
        for key, value in changes:
            with self.subTest(key=key, value=value):
                self.reset()
                self.manifest(lambda m: m.update({key: value}))
                self.refuse()
        for name in ("../outside", "/outside", "manifest.json", "original-container.mkv"):
            self.reset()
            self.manifest(lambda m: m["components"][0].update(name=name))
            self.refuse()
        self.reset()
        self.manifest(lambda m: m["components"].append(m["components"][0]))
        self.refuse()

    def test_duplicate_json_nonfinite_oversized_and_wrong_typed_objects(self):
        path = self.package / "manifest.json"
        good = path.read_bytes()
        for data in (b'{"version":0,"version":0}', b'{"version":NaN}', b'[]',
                     b'"text"', b'[' * 2000, b' ' * ((1 << 20) + 1)):
            with self.subTest(size=len(data)):
                path.write_bytes(data)
                self.refuse()
        path.write_bytes(good)

    def test_forged_original_track_and_configuration_repair_hashes_still_refuse(self):
        for name in ("original-track-entry-payload.bin", "hevc-configuration.bin"):
            self.reset()
            path = self.package / name
            data = bytearray(path.read_bytes())
            data[-1] ^= 1
            path.write_bytes(data)
            self.repair(name)
            self.refuse()

    def test_forged_index_repairs_hash_but_cannot_change_packet_nal_pts_offset_or_bytes(self):
        changes = {"packet_index": 1, "nal_index": 1, "pts_ns": 0, "index": False,
                   "original_payload_offset": 0, "archive_delimiter_offset": 1,
                   "payload_bytes": 1, "payload_sha256": "0" * 64, "kind": "future"}
        for key, value in changes.items():
            with self.subTest(key=key):
                self.reset()
                path = self.package / "rpu-index.jsonl"
                refs = read_rows(path)
                refs[0][key] = value
                write_rows(path, refs)
                self.repair(path.name)
                self.refuse()

    def test_forged_audit_order_timing_summary_flags_and_complete_repair_hash_refuse(self):
        for kind, key, value in (("begin", "configuration_sha256", "0" * 64),
                                 ("packet", "pts_ns", 0), ("packet", "invisible", True),
                                 ("packet", "index", False), ("rpu-summary", "summary", {}),
                                 ("complete", "packet_sequence_sha256", "0" * 64),
                                 ("complete", "enhancement_nals", 0)):
            self.reset()
            path = self.package / "source-audit.jsonl"
            audit = read_rows(path)
            next(row for row in audit if row["kind"] == kind)[key] = value
            write_rows(path, audit)
            self.repair(path.name)
            self.refuse()

    def test_forged_rpu_and_full_container_content_hashes_refuse(self):
        for name in ("original-rpu.bin", "original-container.mkv"):
            self.reset("full")
            path = self.package / name
            data = bytearray(path.read_bytes())
            data[-1] ^= 1
            path.write_bytes(data)
            self.repair(name)
            self.refuse()

    def test_trailing_missing_duplicate_sorted_rows_and_archive_bytes_refuse(self):
        for name in ("rpu-index.jsonl", "source-audit.jsonl"):
            for action in ("extra", "missing", "sorted", "partial", "wide"):
                self.reset()
                path = self.package / name
                rows = read_rows(path)
                if action == "extra":
                    rows.append(rows[-1])
                elif action == "missing":
                    rows.pop()
                elif action == "sorted":
                    rows.reverse()
                write_rows(path, rows)
                if action == "partial":
                    path.write_bytes(path.read_bytes()[:-1])
                elif action == "wide":
                    path.write_bytes(b" " * (check.LINE_LIMIT + 1) + b"\n")
                self.repair(name)
                self.refuse()
        self.reset()
        with (self.package / "original-rpu.bin").open("ab") as output:
            output.write(b"extra")
        self.repair("original-rpu.bin")
        self.refuse()

    def test_symlink_hardlink_fifo_directory_component_and_package_refuse(self):
        for name in ("manifest.json", "original-rpu.bin"):
            for mode in ("symlink", "hardlink", "fifo", "directory"):
                self.reset()
                path = self.package / name
                retained = self.path / (name + mode)
                path.rename(retained)
                if mode == "symlink":
                    path.symlink_to(retained)
                elif mode == "hardlink":
                    os.link(retained, path)
                elif mode == "fifo":
                    os.mkfifo(path)
                else:
                    path.mkdir()
                self.refuse()
        alias = self.path / "alias"
        alias.symlink_to(self.package, target_is_directory=True)
        with self.assertRaises((check.Refused, OSError)):
            check.validate(self.source, alias, HELPER)
        self.source.unlink()
        self.source.symlink_to(self.root / "generated-source.mkv")
        self.refuse()

    def test_source_bytes_and_identity_replaced_or_mutated_during_check_refuse(self):
        real = check.helper_rows
        for replacement in (False, True):
            with self.subTest(replacement=replacement):
                original = self.source.read_bytes()
                @contextlib.contextmanager
                def changed(*args):
                    with real(*args) as rows:
                        yield rows
                    if replacement:
                        other = self.path / "replacement"
                        other.write_bytes(original)
                        other.replace(self.source)
                    else:
                        data = bytearray(original)
                        data[-1] ^= 1
                        self.source.write_bytes(data)
                with patch.object(check, "helper_rows", changed):
                    self.refuse()
                self.source.write_bytes(original)

    def test_component_and_directory_replaced_during_check_refuse(self):
        real = check.helper_rows
        for directory in (False, True):
            self.reset()
            @contextlib.contextmanager
            def changed(*args):
                with real(*args) as rows:
                    yield rows
                if directory:
                    self.package.rename(self.path / "old-package")
                    shutil.copytree(self.root / "metadata", self.package)
                else:
                    path = self.package / "original-rpu.bin"
                    data = path.read_bytes()
                    path.unlink()
                    path.write_bytes(data)
            with patch.object(check, "helper_rows", changed):
                self.refuse()

    def fake(self, program):
        path = self.path / "generated-helper"
        path.write_text("#!" + sys.executable + "\n" + program)
        path.chmod(0o700)
        return path

    def test_nonzero_helper_even_with_complete_valid_rows_refuses(self):
        output = subprocess.check_output([HELPER, "mkv-summary", self.source])
        fake = self.fake("import sys\nsys.stdout.buffer.write(" + repr(output) + ")\nsys.exit(1)\n")
        self.refuse(fake)

    def test_malformed_incomplete_and_unknown_helper_rows_refuse(self):
        for data in (b"not-json\n", b'{"kind":"begin"}\n', b'{"kind":"future"}\n',
                     b' ' * (check.LINE_LIMIT + 1), b'{"kind":"resources","kind":"complete"}\n'):
            self.refuse(self.fake("import sys\nsys.stdout.buffer.write(" + repr(data) + ")\n"))

    def test_owned_deadline_kills_and_joins_helper_and_pipe_holding_descendant(self):
        for descendant in (False, True):
            pid_path = self.path / "pid"
            program = "import os, time\n"
            if descendant:
                program += "pid=os.fork()\nif pid: os._exit(0)\n"
            program += "open(" + repr(str(pid_path)) + ", 'w').write(str(os.getpid()))\ntime.sleep(30)\n"
            self.refuse(self.fake(program), timeout=0.5)
            pid = int(pid_path.read_text())
            # Direct children are joined; on Darwin descendants are reaped by launchd.
            # A terminated descendant may briefly be a zombie, never a live sleeper.
            state = subprocess.run(["ps", "-p", str(pid), "-o", "state="],
                                   capture_output=True, text=True).stdout.strip()
            self.assertTrue(not state or state.startswith("Z"), state)

    def test_interrupted_semantic_comparison_joins_owned_child_before_propagating(self):
        class Cancelled(BaseException):
            pass
        started = []
        real = subprocess.Popen
        def tracked(*args, **kwargs):
            child = real(*args, **kwargs)
            started.append(child)
            return child
        with patch.object(check.subprocess, "Popen", tracked), \
                patch.object(check, "same_json", side_effect=Cancelled):
            with self.assertRaises(Cancelled):
                self.validate()
        self.assertEqual(len(started), 1)
        self.assertIsNotNone(started[0].returncode)
        self.assertTrue(started[0].stdout.closed)

    def test_cli_failure_keeps_private_paths_out_of_diagnostics(self):
        result = subprocess.run([sys.executable, str(Path(check.__file__)), "--source", str(self.source),
                                 "--package", str(self.path / "missing"), "--audit-helper", str(HELPER)],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertNotIn(str(self.path), result.stdout + result.stderr)
        self.assertEqual(result.stdout, "")

    def test_source_bound_producer_packages_pass_independent_semantic_verifier(self):
        root = self.path / "source-bound"
        root.mkdir()
        environment = dict(os.environ, STAXRIP_GENERATED_BOUND_COMPANION_DIRECTORY=str(root))
        subprocess.run(["cargo", "test", "--locked", "--manifest-path",
                        str(ROOT / "Tools/DolbyMetadataAudit/Cargo.toml"),
                        "source_bound_companion_packages_preserve_originals_and_settle_descriptors"],
                       env=environment, check=True, stdout=subprocess.DEVNULL)
        source = root / "generated-source.mkv"
        before = source.read_bytes()
        for mode in ("metadata", "full"):
            package = root / mode
            components = {p.name: p.read_bytes() for p in package.iterdir()}
            result = check.validate(source, package, HELPER)
            self.assertEqual((result["packets"], result["records"]), (1, 2))
            self.assertEqual(components, {p.name: p.read_bytes() for p in package.iterdir()})
            self.assertFalse(json.loads(components["manifest.json"])["source_path_identity_bound"])
        self.assertEqual(source.read_bytes(), before)

    def test_owned_stage_producer_packages_pass_independent_semantic_verifier(self):
        root = self.path / "owned-stage"
        root.mkdir()
        environment = dict(os.environ, STAXRIP_GENERATED_STAGED_COMPANION_DIRECTORY=str(root))
        subprocess.run(["cargo", "test", "--locked", "--manifest-path",
                        str(ROOT / "Tools/DolbyMetadataAudit/Cargo.toml"),
                        "owned_stage_packages_preserve_originals_and_match_disk_receipts"],
                       env=environment, check=True, stdout=subprocess.DEVNULL)
        source = root / "generated-source.mkv"
        before = source.read_bytes()
        for mode in ("metadata", "full"):
            package = root / mode
            components = {p.name: p.read_bytes() for p in package.iterdir()}
            result = check.validate(source, package, HELPER)
            self.assertEqual((result["packets"], result["records"]), (1, 2))
            self.assertEqual(components, {p.name: p.read_bytes() for p in package.iterdir()})
            self.assertFalse(json.loads(components["manifest.json"])["source_path_identity_bound"])
        self.assertEqual(source.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
