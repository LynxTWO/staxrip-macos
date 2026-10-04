# Minimal decoder runtime prerequisite
Version: 0.1. Date: 2026-10-04. Scope: D-097 / R-059 / Slice 049.
Status: macOS 14 deployment declarations and development relocation qualified;
complete compatible-build source check running; hardened signing/native admission open.

## Need and effect

D-096 proved complete base-picture/raw-RPU association using installed FFmpeg,
and generated cases on a private minimal build. Neither qualified a deployable
native dependency. This unit preserves source, current recovery, owner session
and prior outputs while checking a reproducible compatible development candidate.
No app dependency, runtime conversion, owner encode, audio listening, merge or release.

## Build identity and compatibility

The source is unmodified official FFmpeg 9.0.2, archive SHA256
8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e.
After both builds, all 10,399 source-file contents agree with the pinned archive.
The candidate uses shared libavutil 61.1.102, libavcodec 63.1.102 and libavformat
63.1.102. Only HEVC decoding/parsing, Matroska demuxing and local file protocol
are enabled. GPL, nonfree, version3, autodetection, network, hardware VideoToolbox,
programs, avdevice, avfilter, swscale and swresample are disabled.

The first private build inherited macOS 27 minimum declarations. That cannot
meet Package.swift's macOS 14 target. Its complete source trial was interrupted,
refused and settled; it is not a passed parity result. Source descriptor and
current recovery bytes stayed unchanged. The replacement out-of-source build
adds -mmacosx-version-min=14.0 to both compile and link flags. Every staged library
and executable now declares macOS 14 in its actual Mach-O LC_BUILD_VERSION.
The development builder sets this target explicitly and rejects unsupported targets.

This is declared deployment compatibility on the current arm64 host, not actual
execution on macOS 14 or x86_64. System dependencies include libSystem and Apple's
CoreFoundation, CoreVideo and CoreMedia frameworks. No claim of libSystem-only
dependency or qualification of every older-platform API is made.

## Generated execution and relocation

Fifteen reference tests passed with the macOS 14 minimal build. The new test checks
the actual produced Mach-O minimum and refuses an unsupported build target without
creating an output. Existing source/protocol/resource/interruption/no-overwrite
checks remain unchanged. The reader workflow now runs this generated suite when
either development tool changes; no application assertion or deadline changes.

Private copied libraries use relative sibling loader references. Executables use
their adjacent Frameworks directory. After moving the stage, runtime symbol queries
locate all three libraries inside that stage and report LGPL 2.1-or-later with the
expected configuration. All five object signatures verify; load commands retain
only relative candidate and Apple system dependencies, with no inherited rpath,
original prefix or Homebrew library reference. Ambient loader overrides are removed.
Original installed executable/library hashes remain unchanged.

The relocated compatible executable passes ten accepted cases: one/four-thread
B-frame, BlockGroup, variable-VINT, codec-conformance and complete open-GOP inputs.
Five surplus/missing/negative/duplicate-timing/CRA-prefix cases refuse as required.
The generated conformance case retains coded 176x112, crop [0,14,0,14], visible
162x98 and independent container crop/display declarations. Relocation does not
silently apply codec or container cropping.

## Retained signing and driver failures

The first hardened-runtime trial used ad-hoc signatures. Library validation
rejected the mapped library's Team ID. That failure is retained; it does not qualify
hardened loading. A subsequent Developer ID signing operation did not settle during
bounded observation; only its verified owned codesign child was terminated. No
completed Developer ID or notarization claim follows, and the reason for the signing
wait remains unknown. No library-validation entitlement or persistent setting changed.

The successful relocation candidate uses ordinary ad-hoc development signing without
the hardened-runtime option. It proves development portability only. Developer ID
signing/loading and native packaging remain open prerequisites. The native app and
its signing configuration are untouched.

A private fixture driver initially failed to classify the expected duplicate-PTS
SQLite IntegrityError as refusal after ten accepted cases. The driver was corrected
to retain the checker's existing SQLite-refusal contract; the full fifteen-case
relocated run then passed. No decoder behavior or public checker assertion changed.

## Source material and remaining qualification

An owned private candidate folder contains the pinned source archive, five upstream
license files, normalized configure options and build notes. Source/configuration,
input and relocated binary hashes are bound in private receipts. No source archive,
library, media payload, personal path or credential is committed or distributed.
Corresponding public source hosting, app/download attribution and the owner project
license remain distribution obligations. This is preparation, not a blanket compliance
claim. See [FFmpeg's build/license guidance](https://ffmpeg.org/legal.html) and
[Apple's code-signing guidance](https://developer.apple.com/library/archive/technotes/tn2206/_index.html).

The complete source check on the compatible build is still running with D-096's
unchanged four-thread configuration, association contract, source checks and bounds.
It has no accepted result until both producers exit successfully and the final
source fingerprint agrees. Timed resource results are observations, not enforced
whole-process memory guarantees or combined simultaneous process-footprint bounds.

Open gates: completed compatible source association, native process ownership and
resource policy, hardened signed loading, older-platform execution, actual decoded
sample/rendering parity, EL pairing/reconstruction, crop/resize brightness/statistics,
conversion/companion publication and distribution. D-096's completed source association
does not establish these claims. PR 71's automatic hosted timing failures are retained
in HOSTED-QUALIFICATION-REFRAME.md; no retry or timing investigation follows.
