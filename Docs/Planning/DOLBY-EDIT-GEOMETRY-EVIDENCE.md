# Dolby edit geometry proposals
Version: 0.1. Date: 2026-10-04. Scope: D-098 / R-059 / Slice 049.
Status: pure geometry, generated picture, ordinary app regression and development build passed;
no edited-Dolby admission or metadata writer.

## Problem and boundary

Crop and resize need explicit coordinate origins before metadata can be transformed.
DolbyEditGeometry is an internal pure proposal function. It reads no file, invokes no
process, persists no state and writes no RPU. EncodePlan and the native dynamic-HDR
refusal are unchanged. No edited-Dolby export or new decoder dependency is admitted.

Callers provide coded size, codec window, codec-visible container pixels, container
crop, actual decoder size/origin, active-area basis, user crop, actual scaled size,
padding and known sample aspect. They must establish those facts independently.
Coded, codec-visible and container-visible origins are distinct. An unresolved origin,
orientation or sampling mode refuses. Rotation, mirroring and interlacing need separate
contracts. Container display ratios/physical dimensions do not become pixel sizes.

The supported subset requires container pixel declarations to match codec-visible
size. It expresses one composite pixel crop in the actual decoder's coordinates;
codec or container windows already applied by that decoder are not applied again.
The effective crop, remaining raster, scaled raster and padding follow an even 4:2:0
sample grid. Declaration windows are coordinate steps, not extra pixel operations.
Odd luma metadata offsets remain valid. Chroma phase, actual resampling and metadata
reference semantics remain separate physical-picture qualifications.

## Exact arithmetic and information consequences

The active region is a half-open luma rectangle. Translate its declared basis into
coded coordinates, intersect with the composite crop, translate to crop origin, scale
each edge by the corresponding rational raster ratio, then add padding. Retain reduced
integer fractions without floating-point rounding. An integer offset proposal refuses
fractional edges rather than silently choosing floor, ceil or nearest. Empty regions
and malformed or out-of-bounds inputs refuse.

Sample aspect after resizing is source SAR times cropped width times scaled height,
divided by cropped height times scaled width. This preserves the cropped picture's
intended displayed proportions; padding adds canvas area independently. The returned
fraction is a proposal, not codec/container SAR representability or output verification.
See [FFmpeg scale and crop semantics](https://ffmpeg.org/ffmpeg-filters.html#scale-1).

The proposal separately reports whether cropping clipped the declared region and
whether raster resizing was requested. Those are geometry facts only. A retained
metadata region is not measured black bars or a claim that brightness analysis is
unchanged. Padding/overlays, kernel support, chroma resampling, transfer/color/range,
bit depth and resulting-picture statistics still require explicit qualification.

All dimensions are bounded at 8192, with a 4096x4096 total-pixel ceiling per raster.
Offsets are 0...8191; input SAR components are 1...1,000,000. Inputs are checked before
sums/products, and intermediate rational products fit Int64 within these bounds.
These arithmetic bounds are unrelated to a decoder's whole-process memory policy.

## Generated checks

Eight new tests cover codec cropping once, equivalent coded/codec/container bases,
odd metadata offsets, intersected active content, translated padding, exact fractional
edges, anamorphic sample shape, independent per-shot regions, clipping/resize facts,
composed declaration windows and unresolved/invalid/chroma/empty/bounds refusals.

A coded 176x112 picture with right/bottom codec crop 14 resolves to 162x98. A decoder
that already returns that visible raster receives zero additional codec crop. The
same active region expressed in different established bases maps identically.

For cropped 12x8 scaled to 10x6, generated metadata maps to edges 5/6, 15/2, 3/4
and 21/4. Integer metadata proposals refuse. A known 8:9 source sample shape resized
from 12x8 to 24x12 gives a reduced 2:3 output sample aspect.

An actual generated 16x10 gray image contains a white 8x6 region at odd metadata
origin (3,1). A composite even crop produces 12x8, nearest scaling produces 24x16,
and an optional even border produces 30x18. Every resulting black/white sample agrees
with the proposed active-area bounds, with and without padding; source bytes are
unchanged. This is a luma/nearest-grid check, not HDR/chroma/filter-kernel quality or
Dolby rendering. All files are owned generated temporary fixtures; no owner identifier
or media payload enters public tests/evidence.

The initial ordinary app run passed 318 tests/77 suites in 236.131 seconds. After
adding explicit clipping/resize facts and the eighth test, the final ordinary run
passed all 319 tests/77 suites in 217.521 seconds. Optimized build.command completed;
outer app and existing bundled Rust helper signatures verify. This is ad-hoc
local development signing, not Developer ID/notarized distribution. No FFmpeg library
or decoder reference is added to the app. No native control/view/session schema changed;
there is no new owner-source walkthrough or heard VoiceOver claim.

## Remaining gates

Every-picture/shot timeline and source identity binding, decoded input/output
validation, kernel/rounding/chroma/color/brightness qualification, artistic trims,
metadata authoring, native conversion and original companion publication remain open.
No coordinate proposal bypasses those gates. D-097's compatible complete-source association passed independently; its hardened
signing/resource/native integration gates are still open.
