# Verified original-video copy evidence
Version: 0.1. Date: 2026-10-01. Status: Implementation qualification in progress.

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

## Remaining gates

Native light/dark controls, correction/save/reopen/export, optimized build, full ordinary local/hosted tests and final planning audit remain pending. No slice acceptance or full-program completion claim.
