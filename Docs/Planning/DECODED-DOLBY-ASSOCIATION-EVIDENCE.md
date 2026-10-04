# Decoded base-picture/RPU association
Version: 0.1. Date: 2026-10-04. Scope: D-096 / R-059 / Slice 049.
Status: generated and complete private base-picture association checks passed;
no native conversion or new bundled dependency.

## Problem and implementation

An encoded census and PTS sorting do not prove which decoded picture receives an
RPU or distinguish CRA nonoutput access units. Consequence is user_data for later
preservation/conversion claims; this reference remains local_only.

Tools/DolbyFrameReference uses installed FFmpeg libraries in a separate development
executable. Original packet opaque provenance, positions/PTS/payload hashes and
escaped raw frame-RPU hashes must agree with the independent bounded Rust census.
A disk-backed SQLite checker requires unique original timing/positions, one RPU
per packet, unchanged progressive ten-bit geometry/SAR and complete packet/frame
coverage through decoder drain. Both producers must exit zero after complete output;
final whole-source fingerprint and descriptor/path identity must agree. No full-film
packet/frame/metadata array or payload is retained in memory.

The additive Rust block_input_byte_offset identifies Block payload before its
variable track VINT, unlike the existing encoded-video input_byte_offset. FFmpeg
position refers to the former; generated one/two/three-byte VINT tests distinguish
them. Existing packet proof bytes/protocol versions are unchanged. Opaque propagation
can be many-to-many; direct wire and coverage checks enforce this strict subset.

Pinned hevc_parser 0.6.10 was evaluated but not added: its public parser retains
complete NAL/frame arrays and low-level APIs are private. FFprobe shows provenance
but not raw RPU digests. The C reference uses custom local-descriptor I/O and the
software HEVC decoder. It is unbundled; local FFmpeg enables GPL components. Later
distribution needs separate license/dependency/resource qualification.

## Generated and local checks

Verified observed_behavior at FFmpeg 9.0.2/Rust 1.98.1/Python 3.14.7: 17 locked Rust
tests, formatting, warnings-denied Clippy and optimized reader build passed. Fourteen
Python integration/refusal tests passed with multiple mutations; Clang warnings-denied
build passed. Ordinary app regression passed 311 tests/76 suites in 207.853 seconds
with default assertions/scheduling. No native view/app packaging changes; the installed
D-095 inspector and restored workspace remain untouched.

Actual ten-bit HEVC packet PTS are 0,120,80,40; decoded presentation-order packet
ordinals are 0,3,2,1. Each differing frame RPU digest matches its original packet.
SimpleBlock, BlockGroup and wider VINT cases pass. Surplus/missing RPUs and duplicate
PTS refuse. A byte-identical duplicate that the decoder exposes only once still
refuses. Negative PTS survive the Rust census but the generated FFmpeg packets show
N/A timing; this limitation refuses rather than synthesizes timestamps.

An intact actual 24-picture open GOP passes. Its generated CRA-start subset has more
encoded packets/RPUs than output pictures and fails complete coverage. No access unit
or metadata is removed. Trimming/pre-roll and arbitrary nonoutput access units remain
outside this whole-input contract.

Mutations refuse changed payload/position/size/configuration, wrong frame provenance/
timing/raw-RPU hash/size, interlace/eight-bit output, changing dimensions/crop/SAR,
bad/oversize/repeated-key JSON, reordered/missing/duplicate/trailing records, wrong
completion/resources and a changed final source. Complete output followed by nonzero
exit refuses. Interrupted readers settle their owned child/pipe; actual SQLite page
growth reaches its configured refusal; existing/dangling build destinations remain
untouched. FIFO input fails promptly with generic errors. Build/fixture exports
exclusively create fresh files; no owner names/payloads/sessions/binaries are public.

## Retained full-source configuration observation

The first one-thread reference was interrupted deliberately after 7m30s of decoding
at about 5.59% of the source byte extent. This is byte
position, not decoded-picture completion or a reliable elapsed-time prediction.
It produced no completed association result. The checker refused the interrupted
stream, settled its child and removed its spool; source descriptor/current recovery
bytes were unchanged. A four-thread reference was then qualified on the generated
packet/RPU/geometry/CRA cases before a new complete-source pass. Both one/four-thread
B-frame/group/VINT modes retain identical required associations. No application test
assertion or deadline changed. The two-hour development timeout is unchanged.

## Declaration checks on prior encoder trials

All 96 decoded frames in each of six existing HEVC/AV1 excerpts (576 total) match
the initial source declaration: 3840x2160, yuv420p10le, limited range, PQ/BT.2020
with nonconstant-luminance matrix and top-left chroma location. This adds complete
excerpt signal-declaration evidence, not physical-sample/rendered parity or complete
source/output color verification. The original source chroma declaration is not
replaced with an encoder default. Crop/resize must preserve or deliberately resample
chroma location and record the resulting value.

## Minimal decoder dependency feasibility

A private FFmpeg 9.0.2 source build uses the official release archive with SHA256
8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e, checked against
the installed-version Homebrew formula. All 10,399 source files match the archive.
GPL, nonfree, version3, autodetection, network, programs and unneeded libraries are
disabled; HEVC decoder/parser, Matroska demux and local file support are enabled.
All three runtime libraries report LGPL 2.1-or-later. All fourteen generated reference
tests pass against these libraries, including one/four-thread association cases.
This closes only a development build/API feasibility check. No FFmpeg binary/source
is committed or bundled; full-source parity, dependency resource hardening, relocated
library loading, matching notices/source/build material, signing and distribution
remain future gates. Homebrew's read-command auto-enablement of developer mode was
restored immediately; no lasting setting is intended.
See [FFmpeg's license/build guidance](https://ffmpeg.org/legal.html).

## Crop and resize findings

Verified generated source_fact: a 162x98 visible video has a 176x112 coded frame and
codec crop [0,14,0,14], left/right/top/bottom. Automatic cropping is disabled in the
reference; normal FFprobe decoding already returns 162x98. Its separate container
declares top crop 1 and display ratio 16:9. Do not remove the codec window twice or
treat a ratio as a pixel raster. Dolby active-area coordinates are separate again.

SLICE-049 binds explicit coordinate basis, per-picture/shot region transforms,
chroma/sample/SAR/kernel semantics, output brightness/statistics and original BL/EL/
RPU retention. Odd luma offsets remain valid independently of pixel-crop alignment.
Dolby's guidance analyzes inside the intended active image. Black-bar removal might
preserve that region, while active crop/resampling cannot be assumed to preserve
analysis values. This is an inference requiring measurement, not edited admission.

## Complete private source outcome

Verified observed_behavior: the complete four-thread pass checked all 120,552 encoded
video packets and all 120,552 decoded base pictures/RPUs with matching original packet
provenance, payload, PTS and escaped raw metadata. Both producers completed/exited
zero and final source fingerprint agreed. Stable coded/visible raster is 3840x2160,
yuv420p10le, zero codec crop and square frame samples. SQLite spool used 24,592,384
bytes; complete pipeline took 2,674.797 seconds. This time includes fingerprints,
bounded census and reference decoding, not an app throughput guarantee.

Original source descriptor and current recovery bytes remained unchanged; no owner
queue execution, source/media write, changed native workspace or published output.
Private receipts bind both executable hashes and checker source. The temporary spool
was removed after its owner closed the database. This establishes decoded base-frame/
raw-RPU association for this source/reference identity, not the excluded rendering,
EL reconstruction, color-sample, edited-picture or audio gates. The minimal LGPL-only
build passed generated tests but has not completed this full private source check.

## Resource and confidence limits

One TiB source; two million selected packets/RPUs/frames; 16 MiB selected packet;
64 KiB RPU/line; 4096x4096 coded-pixel maximum; 64 MiB per FFmpeg allocation;
512 MiB SQLite pages and an 8 MiB page-cache preference with file temporary storage.
These do not establish a whole-process FFmpeg/Python/SQLite heap ceiling or hardened
decoder sandbox. Rust retains its separate tracked-heap boundary. A two-hour development
child timeout refuses; failed/interrupted readers kill/join their owned process and
remove only their temporary spool. Boundary source checks are not an immutable snapshot.

Separate open gates:
general POC mapping, EL/BL pairing/FEL reconstruction, metadata-reference semantics,
brightness/calibrated rendering, edits/HDR10+ authoring, A/V synchronization,
AV1/other-container/player support and native conversion/archive publication.
Hosted PR 70 timing failures remain separate and unexplained. No owner encode,
listening, merge or release.

Primary sources: [FFmpeg raw RPU side data](https://ffmpeg.org/doxygen/trunk/frame_8h_source.html),
[opaque propagation and cropping](https://ffmpeg.org/doxygen/trunk/avcodec_8h_source.html),
[Dolby active-image guidance](https://professionalsupport.dolby.com/s/article/Dolby-Vision-Content-Creation-Best-Practices-Guide?language=en_US),
[metadata levels](https://professionalsupport.dolby.com/s/article/Dolby-Vision-Metadata-Levels?language=en_US).
Invalidate association on source/parser/decoder/framing/timing/geometry changes;
invalidate future edited analysis on any pixel/coordinate/color transform.
