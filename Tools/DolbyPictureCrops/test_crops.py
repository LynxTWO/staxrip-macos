"""Owned generated C crop checks; row-streamed shared-FFmpeg oracle, no app bridge."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shlex
import signal
import stat
import struct
import subprocess
import sys
import tempfile
import time
import unittest

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
sys.dont_write_bytecode = True
sys.path.insert(0, str(HERE.parent / "DolbyPictureSamples"))
from test_samples import OwnedPipe, bounded, identity

class CropTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.path = Path(tempfile.mkdtemp(prefix="staxrip-generated-crops-"))
        print("Retained owned crop fixture:", cls.path, flush=True)
        # Same fixed DEVELOPMENT feature/profile and native lock as D136. This
        # test-only interval covers preparation plus exact compiled generation.
        target = ROOT / "Tools/DolbyMetadataAudit/target/native-development-fixtures"
        target.mkdir(parents=True, exist_ok=True)
        fd = os.open(target / "fixture-build.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
        try:
            s = os.fstat(fd)
            if not stat.S_ISREG(s.st_mode) or s.st_uid != os.geteuid() or s.st_nlink != 1 or stat.S_IMODE(s.st_mode) != 0o600:
                raise RuntimeError("Unsafe native fixture lock")
            deadline = time.monotonic() + 120
            while True:
                try:
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB); break
                except BlockingIOError:
                    if time.monotonic() >= deadline: raise TimeoutError("Native crop fixture lock")
                    time.sleep(.01)
            common = ["--locked", "--features", "development-companion-writer", "--target-dir", str(target),
                "--manifest-path", str(ROOT / "Tools/DolbyMetadataAudit/Cargo.toml"), "--message-format=json"]
            code, output, error = bounded(["cargo", "test", "--no-run", "--lib", "--bins", "--test", "matroska", *common], cls.path, seconds=120)
            if code: raise RuntimeError("Native crop fixture preparation refused: " + error.decode())
            harness = []
            for line in output.splitlines():
                row = json.loads(line)
                if row.get("reason") == "compiler-artifact" and row.get("target", {}).get("name") == "matroska" and row.get("profile", {}).get("test") and row.get("executable"):
                    harness.append(Path(row["executable"]))
            if len(harness) != 1 or not harness[0].is_relative_to(target): raise RuntimeError("Ambiguous native crop generator")
            env = "STAXRIP_GENERATED_DOLBY_REFERENCE_DIRECTORY=" + str(cls.path)
            code, output, error = bounded(["/usr/bin/env", env, str(harness[0]), "actual_hevc_packets_and_rpu_association_match_independent_ffprobe", "--exact"], cls.path, seconds=120)
            if code or b"1 passed; 0 failed" not in output: raise RuntimeError("Native crop generation refused: " + error.decode())
        finally:
            fcntl.flock(fd, fcntl.LOCK_UN)
            os.close(fd) # Once; exception retains owned root, never retries a consumed number.
        cls.probe = Path(os.environ.get("STAXRIP_CROP_PROBE_OUTPUT", str(cls.path / "crop-probe"))).absolute()
        code, _, error = bounded([sys.executable, str(HERE / "build.py"), "--output", str(cls.probe)], cls.path, seconds=80)
        if code: raise RuntimeError("Crop compiler refused: " + error.decode())
        flags = shlex.split(subprocess.check_output(["pkg-config", "--cflags", "--libs", "libavcodec", "libavformat", "libavutil"], text=True, timeout=10))
        cls.planes = cls.path / "sanitized-crop-planes"
        code, _, error = bounded(["clang", "-std=c11", "-Wall", "-Wextra", "-Werror", "-mmacosx-version-min=14.0",
            "-fsanitize=address,undefined", "-fno-omit-frame-pointer", str(HERE / "test_roi.c"), "-o", str(cls.planes), *flags], cls.path, seconds=60)
        if code: raise RuntimeError("Crop sanitizer compiler refused: " + error.decode())

    def command(self, source, threads=1, space="coded", rect=(2,2,16,10)):
        return [str(self.probe), str(source), "--threads", str(threads), "--" + space + "-roi", *map(str,rect)]

    def rows(self, source, threads, space, rect):
        code, output, error = bounded(self.command(source,threads,space,rect),self.path)
        self.assertEqual(code,0,error)
        self.assertTrue(output.endswith(b"\n"))
        self.assertTrue(all(len(line) < 65536 for line in output.splitlines()))
        rows = [json.loads(line) for line in output.splitlines()]
        self.assertEqual(rows[0]["kind"],"crop-begin"); self.assertEqual(rows[-1]["kind"],"crop-complete")
        self.assertTrue(rows[-1]["decoder_drained"] and rows[-1]["descriptor_unchanged"])
        frames = [r for r in rows if r["kind"] == "crop-frame"]
        self.assertEqual(len(frames), rows[-1]["frames"])
        for frame in frames:
            self.assertEqual(frame["request_space"],space); self.assertEqual(frame["requested_rect"],list(rect))
            for flag in ("container_crop_applied","source_roi_provenance_verified","independent_sample_values_verified","edited_picture_semantics_verified"):
                self.assertIs(frame[flag],False)
        return frames

    def oracle(self, source, frames):
        x,y,w,h = frames[0]["coded_rect"]
        command = ["ffmpeg","-v","error","-threads","1","-apply_cropping","0","-i",str(source),"-map","0:v:0",
            "-vf",f"crop={w}:{h}:{x}:{y}:exact=1","-fps_mode","passthrough","-pix_fmt","yuv420p10le","-f","rawvideo","pipe:1"]
        owner = OwnedPipe(command,self.path)
        try:
            for frame in frames:
                self.assertEqual(frame["coded_rect"],[x,y,w,h])
                for i,reported in enumerate(frame["roi"]):
                    width,height = w >> bool(i), h >> bool(i)
                    sha=hashlib.sha256();count=total=squares=0; low,high=1023,0
                    for _ in range(height):
                        row=owner.exact(width*2);sha.update(row)
                        for (v,) in struct.iter_unpack("<H",row):
                            self.assertLessEqual(v,1023);count+=1;total+=v;squares+=v*v;low=min(low,v);high=max(high,v)
                    self.assertEqual(reported,dict(width=width,height=height,samples=count,minimum=low,maximum=high,sum=total,sum_squares=squares,sha256=sha.hexdigest()))
            self.assertEqual(owner.read(1),b""); code,error=owner.finish();self.assertEqual(code,0,error)
        except BaseException:
            if not owner.child.stdout.closed:owner.abort()
            raise

    def test_actual_roi_both_spaces_threads_conformance_and_bframe_reorder(self):
        for case in ("single","group","wide-vint","conformance","whole-gop"):
            source=self.path/(case+".mkv");before=(identity(source),hashlib.sha256(source.read_bytes()).digest())
            for threads in (1,4):
                for space in ("coded","codec-visible"):
                    frames=self.rows(source,threads,space,(2,2,16,10));self.assertEqual(len(frames),24 if case=="whole-gop" else 4)
                    self.oracle(source,frames)
            self.assertEqual(before,(identity(source),hashlib.sha256(source.read_bytes()).digest()))
        source=self.path/"conformance.mkv"
        for threads in (1,4):
            coded=self.rows(source,threads,"coded",(0,0,176,112));visible=self.rows(source,threads,"codec-visible",(0,0,162,98))
            self.assertEqual(coded[0]["codec_crop_left_right_top_bottom"],[0,14,0,14])
            self.assertNotEqual(coded[0]["roi"][0]["sha256"],visible[0]["roi"][0]["sha256"])
            self.oracle(source,coded);self.oracle(source,visible)

    def test_sanitized_atomic_roi_plane_bounds_phase_and_origin(self):
        code,output,error=bounded([str(self.planes)],self.path);self.assertEqual(code,0,error)
        row=json.loads(output)
        for name,values in (("luma",[22,23,32,33]),("u",[111]),("v",[211])):
            self.assertEqual(row[name+"_sha256"],hashlib.sha256(b"".join(struct.pack("<H",v) for v in values)).hexdigest())

    def test_refused_geometry_arguments_input_and_broken_output_never_complete(self):
        source=self.path/"single.mkv"
        commands=[self.command(source,space="container-visible"), self.command(source,threads=2), [str(self.probe)]]
        for rect in ((1,0,16,10),(0,1,16,10),(0,0,15,10),(0,0,16,9),(0,0,0,10),(-2,0,16,10),(8192,0,16,10),(0,0,8192,10),(0,0,4294967294,10)):
            commands.append(self.command(source,rect=rect))
        commands.append(self.command(self.path/"conformance.mkv",space="codec-visible",rect=(160,0,4,2)))
        alias=self.path/"crop-alias";alias.symlink_to(source)
        fifo=self.path/"crop-fifo";os.mkfifo(fifo)
        malformed=self.path/"crop-malformed";malformed.write_bytes(b"not matroska")
        commands.extend(self.command(path) for path in (alias,fifo,malformed))
        for command in commands:
            code,output,error=bounded(command,self.path,seconds=2);self.assertNotEqual(code,0);self.assertNotIn(b'"kind":"crop-complete"',output)
            self.assertNotIn(str(self.path).encode(),error)
        child=subprocess.Popen(self.command(self.path/"whole-gop.mkv"),stdin=subprocess.DEVNULL,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,start_new_session=True)
        child.stdout.close();self.assertGreater(child.wait(timeout=5),0)

    def test_live_cancel_final_substitution_and_exclusive_builder(self):
        original=(self.path/"single.mkv").read_bytes();segment=original.index(bytes.fromhex("18538067"))+4
        width=next(i for i in range(1,9) if original[segment] & (1 << (8-i)));cluster=original.index(bytes.fromhex("1f43b675"),segment+width)
        repeated=bytearray(original[:cluster]);repeated[segment:segment+width]=bytes([255 >> (width-1)])+b"\xff"*(width-1);repeated+=original[cluster:]*2000
        for fault in ("cancel","deadline","substitute"):
            source=self.path/("live-"+fault+".mkv");source.write_bytes(repeated);digest=hashlib.sha256(repeated).digest()
            owner=OwnedPipe(self.command(source),self.path)
            try:
                prefix=bytearray()
                while b'"kind":"crop-frame"' not in prefix:
                    data=owner.read(16384);self.assertTrue(data);prefix.extend(data);self.assertLess(len(prefix),65536)
                state=subprocess.check_output(["ps","-p",str(owner.child.pid),"-o","stat="],text=True).strip();self.assertTrue(state);self.assertNotIn("Z",state)
                if fault in ("cancel","deadline"):
                    if fault == "deadline":
                        owner.deadline = time.monotonic() - 1
                        with self.assertRaises(TimeoutError): owner.read(1)
                    owner.abort();self.assertEqual(owner.child.returncode,-signal.SIGTERM)
                else:
                    held=source.with_suffix(".held");source.rename(held);source.write_bytes(repeated);tail=b"";total=0
                    while True:
                        data=owner.read(16384)
                        if not data:break
                        total+=len(data);self.assertLess(total,64*1024*1024);self.assertNotIn(b'"kind":"crop-complete"',tail+data);tail=data[-64:]
                    code,_=owner.finish();self.assertGreater(code,0);self.assertEqual(hashlib.sha256(held.read_bytes()).digest(),digest)
                self.assertEqual(hashlib.sha256(source.read_bytes()).digest(),digest)
            except BaseException:
                if not owner.child.stdout.closed:owner.abort()
                raise
        for output in (self.probe,self.path/"dangling-output"):
            if output != self.probe:output.symlink_to(self.path/"absent")
            before=output.lstat();code,_,_=bounded([sys.executable,str(HERE/"build.py"),"--output",str(output)],self.path)
            self.assertNotEqual(code,0);self.assertEqual(output.lstat(),before)

if __name__ == "__main__":unittest.main()
