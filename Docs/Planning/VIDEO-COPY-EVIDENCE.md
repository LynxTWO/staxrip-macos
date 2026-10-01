# Verified original-video copy evidence
Version: 0.2. Date: 2026-10-01. Status: Accepted within recorded scope at 22dc1ed.

## Scope

Slice 037, D-067 / R-047. Generated fixtures only. This does not accept production release, real-film/player coverage, HDR or owner audio listening.

## Focused checks

Seven tests in three suites pass locally, including eight actual track/timeline cases, three altered-candidate cases and cancellation during both source capture and output verification. Source MP4 H.264/HEVC VFR copies to MKV/MP4 retain independently decoded picture hashes and frame presentation times. Generated delayed audio, external Unicode SRT and custom chapters retain their tested alignment/content. CFR Matroska H.264/HEVC copies to MP4 pass the same checks. No video encoder is advertised to the copy plan.

Actual missing-packet, changed-picture and 125 ms shifted candidates are refused despite successful encoder exit. No candidate is published, later jobs stay Pending, source/prior output/unrelated staging stay unchanged, and operation-owned staging is removed. Parser tests cover arbitrary chunk boundaries, bounded line/count/size, malformed/missing/duplicate fields and hashes, invalid timing, partial final records and fixed-width round-trips. Real manifest checks cover strict byte count, same-size corruption, 0600 permissions, exclusive creation and symlink refusal. Malformed/truncated/failed probe output refuses. Cancellation awaits tool settlement; the recorded tool PID no longer exists before owned manifest removal.

## Failed experiments and corrections

Initial expanded tests exposed these boundaries rather than qualifying them:

- An initial fixture selected Opus in MP4, which the existing audio guard correctly refused. The positive MP4 matrix now uses AAC; the compatibility guard was not changed.
- Matroska-to-MP4 stream copy dropped an explicit limited-range color declaration. Copy plans now pass through known color/chroma declarations and request MP4 color-box writing when color metadata is present. Strict metadata comparison remains unchanged.
- VFR Matroska nominal packet durations cannot always reproduce MP4 packet durations within one source/output tick. Two generated cases now assert refusal and protected inputs/output absence. CFR Matroska cases separately establish the positive direction. Timing tolerance is unchanged and is not accumulated.
- A parser-detected payload mismatch stops its probe. ToolRunner correctly reports its own cancellation, but initially hid the audit error. The audit now gives a settled parser failure precedence over its internal tool stop, while an actual task cancellation remains cancellation. Changed-picture tests require Failed with packet evidence.
- Generating a changed-picture replacement directly as Matroska initially changed metadata too; it was already refused, but did not isolate payload verification. The fixture now encodes to MP4 and remuxes to Matroska with matching metadata, so the test reaches the packet-content guard.

## Native and local qualification

Product commit 22dc1ed: optimized build passed in 18.16 seconds; ordinary local `swift test` passed all 254 tests in 59 suites in 213.244 seconds. Native macOS 27 walkthrough selected Copy original with an existing two-pixel crop, observed the correction warning, explicitly removed the crop, inspected dark/light layouts and accessibility semantics, saved and reopened the recipe, and switched to HEVC to confirm retained Apple hardware, 8732 kb/s and Thorough settings. Selecting copy again and completing destination review published the generated three-second 640 × 360 H.264 source as MKV with 72 verified encoded packets. Independent decoded pixels matched and 72 frames/three-second duration were confirmed. Stored CRF 17 and the inactive settings also matched the saved document. Source/session bytes were unchanged, owned staging was gone and the prior recovery journal was restored after checking the test job's completed destination and verification evidence. Native accessibility-tree inspection is not heard VoiceOver acceptance.

The automation's path helper initially rejected a folder selection because the native picker canonicalized `/var` to `/private/var`; a fresh picker observation confirmed the intended generated directory before Start. Reopening an unchanged saved session needed no replace confirmation; the helper stopped, and fresh state confirmed the correct saved recipe. Neither changed product behavior.

## Final regression and acceptance

Ordinary hosted [run 36868164452](https://github.com/LynxTWO/staxrip-macos/actions/runs/36868164452) passed all 254 tests in 556.061 seconds at 22dc1ed, following an 86.75-second build. The ordinary local command passed 254 tests in 59 suites in 213.244 seconds. Existing deadlines, assertions and default scheduling were unchanged. The planning audit reports zero findings across 40 selected documents; this is not an all-repository documentation audit.

S37-001 through S37-006 are accepted within the generated/native boundaries above. Arbitrary media/player compatibility, long-film timing, HDR/ten-bit/other codecs, filesystem latency, spoken VoiceOver and production release remain unqualified. Draft PR #54 remains unmerged. No audio listening or full-program completion claim.
