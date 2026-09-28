#!/usr/bin/env python3
"""Serve an existing local listening pack with byte ranges for audio seeking."""
import argparse
import hashlib
import json
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
import re


class RangeHandler(SimpleHTTPRequestHandler):
    def send_head(self):
        self.remaining = None
        path = Path(self.translate_path(self.path))
        header = self.headers.get('Range')
        if not header or not path.is_file():
            return super().send_head()
        size = path.stat().st_size
        match = re.fullmatch(r'bytes=(\d*)-(\d*)', header.strip())
        try:
            if not match or not any(match.groups()):
                raise ValueError()
            first, last = match.groups()
            if first:
                start = int(first); end = min(int(last), size-1) if last else size-1
            else:
                suffix = int(last)
                if suffix <= 0:
                    raise ValueError()
                start = max(0, size-suffix); end = size-1
            if start < 0 or start >= size or end < start:
                raise ValueError()
        except ValueError:
            self.send_response(416)
            self.send_header('Content-Range', f'bytes */{size}')
            self.send_header('Content-Length', '0')
            self.end_headers()
            return None
        stream = path.open('rb'); stream.seek(start)
        self.remaining = end-start+1
        self.send_response(206)
        self.send_header('Content-Type', self.guess_type(str(path)))
        self.send_header('Content-Length', str(self.remaining))
        self.send_header('Content-Range', f'bytes {start}-{end}/{size}')
        self.send_header('Accept-Ranges', 'bytes')
        self.end_headers()
        return stream

    def copyfile(self, source, outputfile):
        if self.remaining is None:
            return super().copyfile(source, outputfile)
        while self.remaining:
            block = source.read(min(65536, self.remaining))
            if not block:
                break
            try:
                outputfile.write(block)
            except (BrokenPipeError, ConnectionResetError):
                break
            self.remaining -= len(block)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('directory', type=Path)
    parser.add_argument('--port', type=int, default=8769)
    args = parser.parse_args()
    root = args.directory.resolve()
    if not (root/'READY.txt').is_file():
        parser.error('The listening pack is incomplete or missing')
    receipt_path = root/'INDEPENDENT-VERIFIED.json'
    if not receipt_path.is_file():
        parser.error('Run the independent Swift listening-pack check before serving')
    receipt = json.loads(receipt_path.read_text())
    if receipt.get('status') != 'passed' or receipt.get('manifestSHA256') != hashlib.sha256((root/'review-key/manifest.json').read_bytes()).hexdigest():
        parser.error('The independent receipt does not match this pack')
    server = ThreadingHTTPServer(('127.0.0.1', args.port), partial(RangeHandler, directory=str(root)))
    print(f'Local listening review: http://127.0.0.1:{server.server_port}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
