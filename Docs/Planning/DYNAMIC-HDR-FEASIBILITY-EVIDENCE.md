# Dynamic HDR feasibility checkpoint
Version: 0.1. Date: 2026-10-03. Scope: D-091/D-092, Slice 049. Status: research checkpoint; no new Dolby Vision runtime admission.

## Complete source classification

Verified source_fact, user_data consequence: all 120552 validated RPUs in the private source classify as Profile 7 MEL, not FEL; this agrees with the earlier independent complete video-packet/RPU count. Complete incremental JSON census checked every record, not just a summary or opening sample. CM v2.9, 1372 scene-refresh entries; observed active-area offsets, target-display trims and mastering/content-light metadata remain private. These luminance fields are metadata declarations, not newly measured picture brightness. Original RPU archive is 27488707 bytes. Full source SHA256 before/after extraction matched; source descriptor and the owner's current recovery bytes were unchanged. The owner updated the recovery configuration since prior work; the new baseline was preserved rather than restoring historical bytes.

Private evidence locator: owned dynamic-HDR source census and extraction receipts, not repository fixtures. Source names, payloads, paths and digests are intentionally not public.

## Actual encoder feasibility

Verified observed_behavior, user_data consequence: installed FFmpeg 9.0.2, x265 and libsvtav1 encoded single-layer converted MEL excerpts with explicit Dolby Vision enabled. HEVC output declares Profile 8.1; AV1 declares Profile 10, both with HDR10 compatibility. Explicitly enabling Dolby Vision is necessary: encoder auto behavior can omit unsupported metadata. The opening 48 frames and three later 96-frame excerpts each passed complete parsed RPU semantic comparison for both codecs, totaling 336 frames per encoder. One later excerpt crosses a metadata change. All mappings, headers and display-management extension values matched the converted reference prefix.

The sole allowed structural normalization is the observed movement of static Level 6 to the first extension position. All other extension order and values remain exact. RPU wire checksums differ after rewriting; each emitted RPU parsed and validated, and checksum differences are recorded separately. This is semantic metadata preservation, not byte-identical encoded video or original Profile 7 preservation. AV1 ITU-T T.35/EMDF RPUs were parsed using pinned MIT libdovi 3.3.2 in a private Rust research helper; dovi_tool 2.3.4 then exported canonical RPU records for comparison. No new helper/library is bundled or used by the app.

AV1 excerpt IVF packet timestamps were unique and monotonic. Research raw input was explicitly assigned 24000/1001 cadence; original container timestamps, future frame edits and complete source/output association are not certified by that result. Full generated controller qualification and independent decoded/display-order auditing remain required.

## Retained failures and corrections

- First HEVC encode refused absent VBV. An owned follow-up with explicit peak/buffer limits succeeded. This was not repaired by disabling Dolby Vision.
- First AV1 research extractor wrote HEVC NAL headers into a raw RPU archive. dovi_tool rejected it. Corrected private extraction uses libdovi's canonical raw-RPU writer; failed artifacts/log remain retained.
- A later seek excerpt had 96 RPUs/packets but 94 decoded pictures, identically before and after profile conversion. Native NAL inspection identified initial CRA followed by two RASL access units that a random-access decoder does not display. Corrected research excerpts retain the original demux, remove only those complete initial nonoutput access units (including their RPUs) from a separate seek-normalized copy, and deliberately encode the first 96 displayed pictures from longer input. No whole-source frame was removed, and no count/timing gate was relaxed. This boundary must be handled explicitly in future trimming/reference mapping.

## Dependency and reconstruction boundary

Local-only development tools: dovi_tool 2.3.4 (MIT), Rust 1.98.1 (Apache-2.0 or MIT), VapourSynth 80 (LGPL-2.1+), FFMS2 5.0 (GPL-2.0+) and Meson 1.12.1 (Apache-2.0). Formula/build receipts are private. FelBaker source pinned at cae66302433578ec62afa8c5c5809e93d0405b2f, GPL-3.0+, with its tracked dovi_tool submodule/libdovi. No FelBaker binary is built or integrated. Its native port's self-generated test hashes and disabled upstream parity comparison do not qualify independent FEL reconstruction. This MEL source does not justify generic FEL discard.

## Product requirements retained

Original encoded preservation, compatible Dolby Vision conversion and HDR10 fallback/new HDR10+ authoring are separate choices. The optional companion archive must retain untouched RPU and enhancement data where present, original configuration, integrity and frame/timing association. RPU-only retention is insufficient for FEL residuals. Its manifest must distinguish original data from any converted metadata and record crop, scale, chroma resampling and frame edits; future reattachment is a new qualification, not an archive guarantee.

Cropping/resizing must validate active-area coordinate changes and chroma siting and assess output picture statistics. Retaining original trims is not authoring HDR10+ metadata. The first proposed compatible conversion contract keeps geometry/cadence unchanged; edited paths remain refused until tested. Device playback, calibrated reference appearance, full-film conversion, runtime companion publication and HDR10+ authoring remain unknown/unimplemented. Audio listening remains parked. Hosted timing qualification remains separately reopened; these experiments neither diagnose nor repair it.

Primary sources: [Dolby profiles and compatibility](https://ott.dolby.com/OnDelKits/Dolby_Vision_Online_Delivery_Kit/v1/Documentation/Specs/Visio_Profiles/help_files/topics/c_dovi_profiles.html), [dovi_tool](https://github.com/quietvoid/dovi_tool), [x265](https://x265.readthedocs.io/en/master/cli.html), [FFmpeg n9.0 Dolby encoder](https://github.com/FFmpeg/FFmpeg/blob/n9.0/libavcodec/dovi_rpuenc.c), [FelBaker](https://github.com/bbeny123/felbaker).

Invalidate source classification if source identity or parser changes; invalidate encoder feasibility on tool/configuration, profile, input metadata or picture/timing transformation changes. Do not promote bounded excerpts to complete output validation.
