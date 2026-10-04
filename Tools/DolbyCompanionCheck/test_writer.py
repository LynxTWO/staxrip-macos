"""Generated executable protocol, parent admission and owned lifecycle checks."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch

import check
import writer

ROOT = Path(__file__).resolve().parents[2]
CARGO = ROOT / 'Tools/DolbyMetadataAudit/Cargo.toml'
BIN = CARGO.parent / 'target/release/staxrip-dolby-companion-writer'
READER = CARGO.parent / 'target/release/staxrip-dolby-metadata-audit'


class WriterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.directory = tempfile.TemporaryDirectory(prefix='staxrip-writer-generated-')
        cls.addClassCleanup(cls.directory.cleanup)
        cls.root = Path(cls.directory.name)
        subprocess.run(['cargo', 'test', '--locked', '--manifest-path', str(CARGO),
                        'owned_stage_packages_preserve_originals_and_match_disk_receipts'],
                       env=dict(os.environ, STAXRIP_GENERATED_STAGED_COMPANION_DIRECTORY=str(cls.root)),
                       check=True, stdout=subprocess.DEVNULL)
        subprocess.run(['cargo', 'build', '--release', '--locked', '--features',
                        'development-companion-writer', '--manifest-path', str(CARGO)],
                       check=True, stdout=subprocess.DEVNULL)

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(dir=self.root)
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name)
        self.source = self.path / 'source.mkv'
        shutil.copyfile(self.root / 'generated-source.mkv', self.source)
        self.stage = self.path / 'stage'
        self.stage.mkdir(mode=0o700)
        self.original = self.source.read_bytes()

    def args(self, operation='a' * 32, mode='metadata'):
        return [BIN, mode, self.source, self.stage, operation,
                *map(str, writer.file_id(self.source.stat()) + writer.file_id(self.stage.stat()))]

    def refusal(self, executable=BIN, **kwargs):
        children = []
        real = subprocess.Popen
        def started(*args, **options):
            child = real(*args, **options)
            children.append(child)
            return child
        with patch.object(writer.subprocess, 'Popen', started):
            with self.assertRaises((check.Refused, OSError)):
                writer.produce(self.source, self.stage, executable, 'metadata', **kwargs)
        for child in children:
            self.assertIsNotNone(child.returncode)
            self.assertTrue(child.stdin.closed and child.stdout.closed)
        self.assertEqual(self.source.read_bytes(), self.original)
        return children

    def fake(self, program):
        path = self.path / 'generated-process'
        path.write_text('#!' + sys.executable + '\n' + program)
        path.chmod(0o700)
        return path

    def test_both_executable_modes_pass_independent_semantics(self):
        for mode in ('metadata', 'full'):
            result = writer.produce(self.source, self.stage, BIN, mode)
            self.assertEqual((result['packets'], result['records']), (1, 2))
            self.assertEqual(result['source_file_id'], writer.file_id(self.source.stat()))
            self.assertEqual(result['stage_file_id'], writer.file_id(self.stage.stat()))
            self.assertFalse(result['semantic_verification'])
            before = {p.name: p.read_bytes() for p in self.stage.iterdir()}
            semantic = check.validate(self.source, self.stage, READER)
            self.assertEqual((semantic['packets'], semantic['records']), (1, 2))
            self.assertEqual(before, {p.name: p.read_bytes() for p in self.stage.iterdir()})
            self.assertFalse(json.loads(before['manifest.json'])['source_path_identity_bound'])
            shutil.rmtree(self.stage)
            self.stage.mkdir(mode=0o700)
        self.assertEqual(self.source.read_bytes(), self.original)

    def test_invalid_arguments_ids_modes_and_control_frames_never_write(self):
        for args in ([], self.args(mode='other')[1:], self.args(operation='X'*32)[1:],
                     self.args(operation='a'*33)[1:], self.args()[1:-1], self.args()[1:-1]+['-1']):
            r = subprocess.run([BIN, *args], input=b'', capture_output=True)
            self.assertNotEqual(r.returncode, 0)
            self.assertEqual(r.stdout, b'')
            self.assertNotIn(str(self.path).encode(), r.stderr)
        for frame in (b'', b'start wrong\n', b'x'*41, b'start '+b'a'*32+b'\nextra',
                      b'start '+b'a'*32):
            r = subprocess.run(self.args(), input=frame, capture_output=True)
            self.assertNotEqual(r.returncode, 0)
            self.assertEqual(json.loads(r.stdout)['kind'], 'ready')
            self.assertNotIn(str(self.path).encode(), r.stderr)
        self.assertEqual(list(self.stage.iterdir()), [])
        self.assertEqual(self.source.read_bytes(), self.original)

    def test_initial_unsafe_preexisting_stage_or_source_refuse_without_launch(self):
        children = []
        for case in ('nonempty', 'permissions', 'source-link'):
            if case == 'nonempty':
                (self.stage/'keep').write_bytes(b'keep')
            elif case == 'permissions':
                (self.stage/'keep').unlink();self.stage.chmod(0o755)
            else:
                self.stage.chmod(0o700);self.source.rename(self.path/'original')
                self.source.symlink_to(self.path/'original')
            self.assertEqual(self.refusal(), children)
        self.source.unlink();(self.path/'original').rename(self.source)
        self.assertEqual(list(self.stage.iterdir()), [])

    def test_source_or_stage_replacement_after_ready_is_refused_before_writes(self):
        for target in ('source', 'stage'):
            def changed():
                if target == 'source':
                    self.source.rename(self.path/'old-source');self.source.write_bytes(self.original)
                else:
                    self.stage.rename(self.path/'old-stage');self.stage.mkdir(mode=0o700)
            with self.assertRaises(check.Refused):
                writer._produce(self.source, self.stage, BIN, 'full', threading.Event(), 10, changed)
            self.assertTrue(all(p.stat().st_size == 0 for p in self.stage.iterdir()))
            if target == 'source':
                self.source.unlink();(self.path/'old-source').rename(self.source)
                shutil.rmtree(self.stage);self.stage.mkdir(mode=0o700)
            else:
                self.assertEqual(list((self.path/'old-stage').iterdir()), [])
        self.assertEqual(self.source.read_bytes(), self.original)

    def test_ready_wait_cancellation_deadline_and_interruption_settle_real_child(self):
        for action in ('cancel', 'deadline', 'interrupt'):
            stop = threading.Event()
            child = None
            class Interrupted(BaseException):
                pass
            expected = Interrupted if action == 'interrupt' else check.Refused
            with self.assertRaises(expected):
                with writer.owned_process(self.args(), stop, 0.15 if action == 'deadline' else 10) as (child, read, _, _):
                    self.assertEqual(read()['kind'], 'ready')
                    if action == 'interrupt':
                        raise Interrupted()
                    if action == 'cancel':
                        stop.set()
                    read()  # Still awaiting start; monitor terminates and settles it.
            self.assertIsNotNone(child.returncode)
            self.assertTrue(child.stdin.closed and child.stdout.closed)
            self.assertEqual(list(self.stage.iterdir()), [])
        shutil.rmtree(self.stage)  # Only after all owned writers have settled.
        self.assertEqual(self.source.read_bytes(), self.original)

    def test_precancel_does_not_start_and_cancelled_settled_result_is_not_admitted(self):
        stop = threading.Event();stop.set()
        self.assertEqual(self.refusal(cancel=stop), [])
        stop.clear()
        real = writer.checked_content
        def cancel_after_disk(fd, cancel):
            result = real(fd, cancel);stop.set();return result
        with patch.object(writer, 'checked_content', cancel_after_disk):
            children = self.refusal(cancel=stop)
        self.assertEqual(len(children), 1)
        self.assertEqual(children[0].returncode, 0)
        self.assertTrue((self.stage/'manifest.json').exists())

    def test_cancel_requested_inside_actual_disk_read_is_observed(self):
        stop = threading.Event()
        real = check.read_at
        def cancelled_read(*args):
            data = real(*args);stop.set();return data
        with patch.object(check, 'read_at', cancelled_read):
            children = self.refusal(cancel=stop)
        self.assertEqual(children[0].returncode, 0)
        self.assertTrue((self.stage/'manifest.json').exists())

    def test_invalid_readiness_and_bounded_output_refuse_and_join(self):
        for data in (b'not-json\n', b'{"kind":"ready","protocol":true}\n',
                     b'{"kind":"ready","kind":"ready"}\n', b'x'*(writer.LINE_LIMIT+1)):
            program = 'import sys,time\nsys.stdout.buffer.write('+repr(data)+');sys.stdout.flush()\ntime.sleep(30)\n'
            self.assertEqual(len(self.refusal(self.fake(program), timeout=2)), 1)
            self.assertEqual(list(self.stage.iterdir()), [])

    def test_forged_or_nonzero_complete_receipts_never_admit(self):
        for fault in ('operation', 'extra', 'duplicate', 'bytes', 'identity', 'members', 'heap', 'nonzero', 'trailing'):
            program = ('import sys,json,subprocess\n'
                       'op=sys.argv[4]\nprint(json.dumps(dict(kind="ready",protocol=1,operation=op)),flush=True)\n'
                       'start=sys.stdin.buffer.read(41)\n'
                       'r=subprocess.run(['+repr(str(BIN))+',*sys.argv[1:]],input=start,capture_output=True,check=True)\n'
                       'value=json.loads(r.stdout.splitlines()[1])\n')
            changes = {'operation':'value["operation"]="b"*32', 'extra':'value["unknown"]=1',
                       'bytes':'value["components"][0]["bytes"]=True',
                       'identity':'value["source_file_id"][1]=0', 'members':'value["components"][0]["name"]="../outside"',
                       'heap':'value["heap_limit"]=True'}
            program += changes.get(fault,'pass')+'\n'
            program += 'wire=json.dumps(value)\n'
            if fault == 'duplicate':
                program += 'wire=wire[:-1]+\', "kind":"staged"}\'\n'
            program += 'print(wire,flush=True)\n'
            if fault == 'trailing':
                program += 'print("extra",flush=True)\n'
            if fault == 'nonzero':
                program += 'sys.exit(1)\n'
            self.refusal(self.fake(program))
            self.assertTrue((self.stage/'manifest.json').exists())
            shutil.rmtree(self.stage);self.stage.mkdir(mode=0o700)

    def test_eof_without_exit_still_expires_and_settles(self):
        program = ('import sys,json,os,time\n'
                   'print(json.dumps(dict(kind="ready",protocol=1,operation=sys.argv[4])),flush=True)\n'
                   'sys.stdin.buffer.read()\n'
                   'print(json.dumps(dict(kind="staged")),flush=True)\n'
                   'os.close(1)\ntime.sleep(30)\n')
        self.assertEqual(len(self.refusal(self.fake(program), timeout=0.5)), 1)
        self.assertEqual(list(self.stage.iterdir()), [])

    def test_pipe_holding_descendant_deadline_joins_direct_child(self):
        pid_path = self.path/'pid'
        program = ('import os,time,json,sys\n'
                   'print(json.dumps(dict(kind="ready",protocol=1,operation=sys.argv[4])),flush=True)\n'
                   'sys.stdin.buffer.read()\npid=os.fork()\nif pid: os._exit(0)\n'
                   'open('+repr(str(pid_path))+',"w").write(str(os.getpid()))\ntime.sleep(30)\n')
        children = self.refusal(self.fake(program), timeout=0.5)
        self.assertEqual(len(children), 1)
        pid = int(pid_path.read_text())
        state = subprocess.run(['ps','-p',str(pid),'-o','state='],capture_output=True,text=True).stdout.strip()
        self.assertTrue(not state or state.startswith('Z'), state)


if __name__ == '__main__':
    unittest.main()
