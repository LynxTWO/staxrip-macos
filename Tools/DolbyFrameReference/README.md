# Decoded base-picture reference — development only

This separate macOS development tool checks a deliberately narrow whole-input
Matroska HEVC packet/frame/RPU association contract. It does not enable an app
conversion, edit, archive publication or original enhancement reconstruction.
The native app neither builds nor invokes it. Existing installed FFmpeg libraries
are required; nothing is downloaded by these tools. Local qualification uses
FFmpeg 9.0.2, Python 3.14 and macOS. Earlier library/platform versions are unqualified.

Build the independent reference into a fresh private output location:

```
python3 Tools/DolbyFrameReference/build.py --output /your/private/reference
cargo build --release --locked --manifest-path Tools/DolbyMetadataAudit/Cargo.toml
python3 Tools/DolbyFrameReference/check.py /your/private/input.mkv \
  --audit Tools/DolbyMetadataAudit/target/release/staxrip-dolby-metadata-audit \
  --reference /your/private/reference
python3 Tools/DolbyFrameReference/test_reference.py -v
```

Clang and pkg-config compile against already installed libavformat/libavcodec/
libavutil. The builder refuses existing destinations and exclusively publishes
the completed executable. Use --threads 1 only for the separately tested single-thread configuration; the checker
requires the requested thread count in the reference header. This reference dynamically links the installed FFmpeg
build; the local build enables GPL components. It is not bundled, copied into
the app or represented as a new MIT dependency. Any later distribution needs
its own license, dependency, signing and resource review. No FFmpeg library
implementation source is copied here.

## Evidence contract

The checker fingerprints the complete regular source before any work. It streams
the bounded Rust protocol 3 into an owned SQLite spool, requiring original unique
signed PTS/block positions, complete source/configuration and ordered packet
digests, one syntax/CRC-validated RPU per packet, resource/completion records and
exit zero. Extra RPUs are refused even when their bytes are identical. Missing
RPUs, invisible packets and ambiguous timing are refused. Audio/subtitle packets
are not decoded or certified.

The C reference reads a local regular descriptor through custom I/O, selects one
HEVC video stream and uses the software HEVC decoder with four threads by default (explicit one-thread mode is also tested), strict error
recognition and automatic codec cropping disabled. It emits original encoded
packet hashes/positions/PTS, and each decoded frame's opaque packet provenance,
frame/best-effort PTS, coded frame raster, unapplied codec crop, sample aspect,
pixel format and escaped raw RPU size/hash. No decoded pixels, metadata payloads
or source paths are emitted. Only progressive yuv420p10le is currently admitted
by the checker. Other formats need separate qualification.

The checker requires direct packet and RPU wire agreement, unchanged frame geometry,
original timing without synthesis, strict display-order PTS and complete one-to-one
packet/frame coverage through decoder drain. `COPY_OPAQUE` is not itself a bijection:
FFmpeg explicitly allows many-to-many mappings. The direct comparisons and coverage
checks enforce this subset rather than assume a general POC mapper. Prefix/nonoutput
CRA access units and references without retained original PTS fail this first contract.
Neither PTS sorting nor count equality alone substitutes for raw-buffer agreement.

Both subprocesses must exit zero after complete output. On refusal/interruption,
the checker kills/joins its owned child, closes the reader and removes only its
temporary spool. A two-hour development process timeout refuses completion; it
is not a product performance guarantee. A final full-source hash and descriptor/
path comparison must agree. Boundary checks are not an immutable media snapshot.

## Geometry interpretation and limits

`geometry` is the frame raster **before codec conformance cropping**, pixel format,
codec crop in left/right/top/bottom order and sample aspect. `codec_visible_size`
subtracts only that codec window. Container crop/display units and Dolby Level 5
offsets remain distinct declarations in the original audit; none is applied by
this reference. A generated 162×98 video demonstrates a 176×112 coded raster and
14-pixel right/bottom codec crop; normal FFprobe decoding already yields 162×98.
Applying that window again would be wrong. The generated container additionally
declares a one-luma-row top crop and a 16:9 display ratio, not a 16×9 pixel raster.
This observation does not establish the coordinate basis for editing its RPU.

Limits: one TiB source; two million selected packets/RPUs/frames; 16 MiB selected
packet; 64 KiB raw RPU/protocol line; 4096×4096 total coded pixels; 64 MiB per
FFmpeg allocation; 512 MiB SQLite pages including indices and an 8 MiB SQLite
page-cache preference. Temporary storage uses files. These limits do **not** prove
a whole-process memory ceiling for FFmpeg/Python/SQLite. Excess resources refuse;
no full-film frame/metadata array is retained. The underlying Rust helper retains
its separate tracked-heap/resource limits. Arbitrary attached streams can still
require an FFmpeg allocation before a selected-packet check; this is not a hardened
untrusted decoder sandbox.

Generated tests use actual reordered ten-bit HEVC and varying RPUs, BlockGroup,
nonminimal track VINT and codec-conformance fixtures. A whole open GOP passes while
its CRA-only start refuses encoded pictures not output by the decoder, without
removing their original metadata. They cover surplus/missing
RPU and duplicate/unusable negative timing refusal; mismatched provenance, raw
metadata, configuration, timestamps, format/geometry/SAR, receipt, ordering,
truncation, trailing records, bounded lines, repeated JSON keys, nonzero exit,
FIFO refusal, interrupted child/pipe settlement, actual SQLite page-cap failure,
existing/dangling build-output preservation and a changed final source. Test-only Rust fixture exports create
fresh files exclusively. Owner media names/payloads never become public fixtures.

This is decoded **base-picture association**, not independent Dolby rendering,
EL/BL pairing or FEL reconstruction, full bitstream conformance, brightness
measurement, crop/resize validity, HDR10+ authoring, A/V synchronization or player
compatibility. Full original preservation still requires matching original base
and enhancement streams. Edited pixels need an explicit coordinate transform and
resulting-picture statistics before any metadata conversion is admitted.

Primary API references: [raw Dolby RPU side data](https://ffmpeg.org/doxygen/trunk/frame_8h_source.html),
[opaque propagation and codec cropping](https://ffmpeg.org/doxygen/trunk/avcodec_8h_source.html).
The development tool is separate from the native helper's packaging contract.

The builder explicitly targets macOS 14.0, matching the native package, and supports
`--deployment-target 14.0`. Its generated test inspects the executable's actual
Mach-O minimum. Linked libraries need their own compatible minimum; targeting the
executable alone cannot make a newer library run on an older Mac. Actual execution
on macOS 14 and x86_64 remains unqualified. The generated suite is included in the
reader workflow for changes to either development tool.

The later private minimal build also explicitly compiles/links for macOS 14.
Development relocation passes generated cases with relative library dependencies,
but hardened Developer ID loading and native integration remain open. See
Docs/Planning/MINIMAL-DECODER-RUNTIME-EVIDENCE.md for retained failures and scope.

A separately built minimal FFmpeg 9.0.2 LGPL-only configuration also passed all fourteen
generated tests. This is private build/API feasibility, not full-source or distribution
qualification. Configure flags, source checksum and limits are recorded in
Docs/Planning/DECODED-DOLBY-ASSOCIATION-EVIDENCE.md. To test a private alternate build,
set PKG_CONFIG_PATH to its lib/pkgconfig for the test/build invocation; the resulting
executable must actually load those libraries, as verified with otool and runtime
license queries. Nothing is installed into the native app by this workflow.
