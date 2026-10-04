#!/usr/bin/env python3
"""Opt-in generated native companion qualification on a newly owned 64 MiB image.

Never accepts an existing image/device. Uncertain test or attachment ownership
retains its receipt and fixture rather than forcing detach or recursive deletion.
"""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import signal
import stat
import subprocess
import tempfile
import uuid


class Refused(Exception):
    pass


def identity(path):
    s = path.lstat()
    return s.st_dev, s.st_ino


def tool_plist(argv):
    r = subprocess.run(argv, capture_output=True, timeout=60)
    if r.returncode:
        raise Refused("Owned image tool refused")
    return plistlib.loads(r.stdout)


def image_entry(info, image):
    matches = [item for item in info.get("images", [])
               if Path(item.get("image-path", "/missing")).resolve() == image]
    if len(matches) != 1:
        raise Refused("Image attachment identity not unique")
    return matches[0]


def bind_image(root, root_id, image, image_id, mount, attached, token):
    if identity(root) != root_id or identity(image) != image_id:
        raise Refused("Owned directory/image substituted")
    s = image.lstat()
    if not stat.S_ISREG(s.st_mode) or s.st_uid != os.geteuid() or s.st_nlink != 1 or not 0 < s.st_size <= 80 << 20:
        raise Refused("Owned image framing refused")
    entry = image_entry(tool_plist(["/usr/bin/hdiutil", "info", "-plist"]), image)
    entities = entry.get("system-entities", [])
    volumes = [x for x in entities if x.get("mount-point") == str(mount)]
    controls = [x for x in entities if x.get("content-hint") == "GUID_partition_scheme"
                and re.fullmatch(r"/dev/disk[0-9]+", x.get("dev-entry", ""))]
    if len(volumes) != 1 or len(controls) != 1:
        raise Refused("Owned image device/mount not unique")
    node, control = volumes[0]["dev-entry"], controls[0]["dev-entry"]
    info = tool_plist(["/usr/sbin/diskutil", "info", "-plist", str(mount)])
    if info.get("FilesystemType") != "apfs" or info.get("DeviceNode") != node or not info.get("VolumeUUID"):
        raise Refused("Owned APFS identity refused")
    ms = mount.lstat()
    if not stat.S_ISDIR(ms.st_mode) or ms.st_dev == root.lstat().st_dev:
        raise Refused("Dedicated mounted filesystem required")
    if attached is not None and (identity(mount) != tuple(attached["mountID"]) or info["VolumeUUID"] != attached["volumeUUID"] or control != attached["controlDevice"] or node != attached["volumeDevice"]):
        raise Refused("Mount/device changed")
    marker = mount / ".staxrip-companion-apfs-fixture"
    if attached is not None:
        m = marker.lstat()
        if not stat.S_ISREG(m.st_mode) or m.st_nlink != 1 or marker.read_text() != "StaxRip companion APFS fixture v1 " + token + "\n":
            raise Refused("Unique mounted marker changed")
    return {"mountID": list(identity(mount)), "volumeUUID": info["VolumeUUID"],
            "volumeDevice": node, "controlDevice": control}


def store(path, value):
    # Receipt lives outside the disposable image, never inside a full volume.
    pending = path.with_suffix(".pending")
    with pending.open("w") as f:
        os.chmod(pending, 0o600)
        json.dump(value, f, indent=2)
        f.write("\n")
        f.flush()
        os.fsync(f.fileno())
    os.replace(pending, path)


def run(receipts):
    project = Path(__file__).resolve().parent.parent
    receipts.mkdir(parents=True, exist_ok=True)
    token = str(uuid.uuid4())
    receipt = receipts / ("companion-apfs-" + token + ".json")
    log = receipts / ("companion-apfs-" + token + ".log")
    root = Path(tempfile.mkdtemp(prefix="staxrip-companion-apfs-", dir=Path(tempfile.gettempdir()).resolve()))
    root_id = identity(root)
    image, mount = root / "fixture.dmg", root / "mount"
    mount.mkdir(mode=0o700)
    state = {"version": 1, "token": token, "state": "creating", "root": str(root),
             "rootID": list(root_id), "image": str(image), "mount": str(mount), "log": str(log)}
    store(receipt, state)
    try:
        created = subprocess.run(["/usr/bin/hdiutil", "create", "-size", "64m", "-fs", "APFS", "-volname", "StaxRipCompanionCapacityFixture", "-type", "UDIF", str(image)], capture_output=True, timeout=60)
        if created.returncode:
            raise Refused("Bounded image creation refused")
        image_id = identity(image)
        state.update(state="attaching", imageID=list(image_id));store(receipt, state)
        attach = tool_plist(["/usr/bin/hdiutil", "attach", str(image), "-mountpoint", str(mount), "-nobrowse", "-owners", "on", "-plist"])
        store(receipts / ("companion-apfs-" + token + "-attach.json"), attach)
        bound = bind_image(root, root_id, image, image_id, mount, None, token)
        marker = mount / ".staxrip-companion-apfs-fixture"
        with marker.open("x") as f:
            os.chmod(marker, 0o600);f.write("StaxRip companion APFS fixture v1 " + token + "\n");f.flush();os.fsync(f.fileno())
        bound = bind_image(root, root_id, image, image_id, mount, bound, token)
        state.update(bound, state="attached", mountDevice=str(bound["mountID"][0]), mountInode=str(bound["mountID"][1]));store(receipt, state)
        env = dict(os.environ, STAXRIP_COMPANION_APFS_RECEIPT=str(receipt))
        with log.open("xb") as output:
            os.chmod(log, 0o600)
            child = subprocess.Popen(["/usr/bin/env", "swift", "test", "--package-path", str(project), "--filter", "CompanionAPFSCapacityTests"], env=env, stdin=subprocess.DEVNULL, stdout=output, stderr=subprocess.STDOUT, start_new_session=True)
            state.update(testPID=child.pid, testGroup=child.pid);store(receipt, state)
            try:
                status = child.wait(timeout=600)
            except (subprocess.TimeoutExpired, KeyboardInterrupt):
                # A Rust process owns a separate group. An outer interrupted test
                # cannot establish all phase settlement by killing Swift alone.
                state.update(state="test-ownership-unsettled");store(receipt, state)
                try:
                    os.killpg(child.pid, signal.SIGTERM)
                    child.wait(timeout=5)
                except (OSError, subprocess.TimeoutExpired):
                    try: os.killpg(child.pid, signal.SIGKILL);child.wait(timeout=5)
                    except (OSError, subprocess.TimeoutExpired): pass
                raise Refused("Interrupted test ownership retained; no detach")
        text = log.read_text(errors="replace")
        settled = "COMPANION_APFS_SETTLED " + token in text.splitlines()
        state.update(testExit=status, directTestChildJoined=True, phaseSettlementMarkerObserved=settled)
        store(receipt, state)
        if not settled:
            raise Refused("Native phase settlement not observed; no detach")
        bind_image(root, root_id, image, image_id, mount, bound, token)
        state.update(state="detaching");store(receipt, state)
        detached = subprocess.run(["/usr/bin/hdiutil", "detach", bound["controlDevice"]], capture_output=True, timeout=60)
        if detached.returncode:
            raise Refused("Owned detach refused; image retained")
        entries = tool_plist(["/usr/bin/hdiutil", "info", "-plist"]).get("images", [])
        if any(Path(x.get("image-path", "/missing")).resolve() == image for x in entries) or mount.lstat().st_dev != root.lstat().st_dev:
            raise Refused("Owned detach not established")
        state.update(state="detached-complete" if status == 0 else "detached-test-failure", ownedDetachVerified=True,
                     metrics=[s for s in text.splitlines() if s.startswith("COMPANION_APFS_RESULT " + token)])
        if status == 0:
            if identity(root) != root_id or identity(image) != image_id: raise Refused("Detached fixture substituted")
            shutil.rmtree(root);state["fixtureImageRemoved"] = True
        store(receipt, state)
        print(json.dumps({k: state[k] for k in ["state", "testExit", "directTestChildJoined", "phaseSettlementMarkerObserved", "ownedDetachVerified", "metrics"]}))
        return status
    except (Refused, OSError, subprocess.TimeoutExpired, KeyboardInterrupt) as error:
        state.update(retained=True, refusal=type(error).__name__ + ": " + str(error));store(receipt, state)
        print("Generated fixture retained for ownership review. Receipt: " + str(receipt))
        return 1


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--run", action="store_true", help="Authorize this disposable generated image test")
    p.add_argument("--receipt-dir", type=Path)
    args = p.parse_args()
    if not args.run or args.receipt_dir is None:
        p.error("Use --run and a private --receipt-dir; no existing image/device is accepted")
    raise SystemExit(run(args.receipt_dir.resolve()))
