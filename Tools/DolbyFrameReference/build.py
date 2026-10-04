#!/usr/bin/env python3
"""Compile a separate local reference using already installed FFmpeg libraries."""
import argparse
import os
from pathlib import Path
import shlex
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--output", type=Path, required=True)
args = parser.parse_args()
destination = args.output.absolute()
if os.path.lexists(destination):
    parser.exit(1, "Refusing to replace an existing build output.\n")
flags = shlex.split(subprocess.check_output(
    ["pkg-config", "--cflags", "--libs", "libavcodec", "libavformat", "libavutil"], text=True))
with tempfile.TemporaryDirectory(prefix="frame-reference-build-", dir=destination.parent) as directory:
    candidate = Path(directory) / "reference"
    subprocess.run(["clang", "-std=c11", "-Wall", "-Wextra", "-Werror",
                    str(Path(__file__).with_name("reference.c")), "-o", str(candidate), *flags], check=True)
    os.link(candidate, destination)  # Atomic exclusive publication; no overwrite race.
