#!/usr/bin/env python3
"""Build a separate DEVELOPMENT probe with installed FFmpeg; never replace output."""
import argparse
import os
from pathlib import Path
import shlex
import shutil
import signal
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--deployment-target", choices=("14.0",), default="14.0")
    args = parser.parse_args()
    destination = args.output.absolute()
    if os.path.lexists(destination):
        parser.exit(1, "Refusing to replace an existing crop build output.\n")
    env = {key: os.environ[key] for key in ("PATH", "PKG_CONFIG_PATH") if key in os.environ}
    flags = shlex.split(subprocess.check_output(["pkg-config", "--cflags", "--libs",
        "libavcodec", "libavformat", "libavutil"], text=True, timeout=10, env=env))
    directory = Path(tempfile.mkdtemp(prefix="crop-probe-build-", dir=destination.parent))
    candidate = directory / "crop-probe"
    joined = False
    try:
        with (directory / "compiler.log").open("xb") as log:
            child = subprocess.Popen(["clang", "-std=c11", "-Wall", "-Wextra", "-Werror",
                "-mmacosx-version-min=" + args.deployment_target,
                str(Path(__file__).with_name("crops.c")), "-o", str(candidate), *flags],
                stdin=subprocess.DEVNULL, stdout=log, stderr=log, env=env, start_new_session=True)
            try:
                # wait timeout does not reap an unfinished child. The owned PID
                # remains reserved until signalling and the following joined wait.
                code = child.wait(timeout=60)
                joined = True
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait(timeout=10)
                joined = True
                raise RuntimeError("Owned crop compiler deadline; retained stage")
        if (directory / "compiler.log").stat().st_size > 1024 * 1024:
            raise RuntimeError("Sample compiler diagnostic bound refused")
        if code:
            raise RuntimeError("Sample compilation refused; inspect retained stage")
        os.link(candidate, destination)  # Exclusive publication; no replacement race.
    except BaseException:
        # Interrupted/unsettled or failed compilation retains its owned artifacts.
        # Direct compiler join is not a universal descendant/power-loss claim.
        print("Retained crop build stage:", directory)
        raise
    else:
        if joined:
            shutil.rmtree(directory)


if __name__ == "__main__":
    main()
