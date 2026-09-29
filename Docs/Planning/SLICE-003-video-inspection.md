# StaxRip Mac Slice 003: Video color and timing inspection
Version: 0.1 Draft. Date: 2026-09-29. Status: In progress.

SLICE STATE
Milestone: Implemented with local numerical, regression and native layout/accessibility evidence; hosted validation and owner review pending.
Blocked by: None.
Evidence so far: VIDEO-INSPECTION-EVIDENCE.md; NON-AUDIO-RESUMPTION.md.
Last audit: 2026-09-29.

## 1. What the slice proves

A user can inspect the source video's declared color and timing information, understand what is missing, and see the current advanced-encoding limitation before choosing a workflow. This is the ColorPlan extension point's information foundation. It does not establish HDR preservation or image correctness.

The current inspector shows dimensions, pixel format and transfer only when present. The advanced plan rejects PQ/HLG and pixel formats other than yuv420p/nv12. Quick Export delegates to Apple presets and has a different contract. These facts should remain explicit.

## 2. The walkthrough

1. Open a local source and choose Inspect media tracks.
2. Read the video track's codec/profile, dimensions and pixel format, then its color primaries, transfer, matrix and range.
3. Inspect average frame rate, reported base frame rate, sample/display aspect ratios, field order and rotation where available. Missing or invalid values are shown as unspecified, not zero or guessed defaults.
4. Read a short explanation of the current advanced export restriction. A PQ/HLG tag identifies a declared HDR transfer; absent tags do not prove SDR. Return to the workspace without changing source data or queue settings.

## 3. In scope, with build order

| Milestone | Contents |
| --- | --- |
| M1 | Extend the internal optional probe fields and add pure presentation helpers for known values, unknown values and validated rational display. Preserve existing stream selection and audio fields. |
| M2 | Group native inspector information into readable picture, color and timing sections with explicit labels and short VoiceOver explanations. Retain raw values alongside friendly recognized names. |
| M3 | Decode generated tagged fixtures, test absent/unknown/malformed values, run regression and inspect native UI at ordinary window size and through its accessibility tree. |

Use the already installed FFmpeg/ffprobe. No new dependency, frame scan, model, network operation or full-file benchmark. Metadata inspection remains bounded by the existing ToolRunner output limit.

## 4. Out of scope, on purpose

HDR encoding, tone mapping, inferred transfer/color tags, dynamic HDR preservation, decoded-pixel validation, variable-frame-rate detection, remux, new filters, audio work, session schema changes, release signing and distribution. HDR preservation and conversion will receive separate acceptance contracts. Audio Slice 002 remains paused and incomplete per the owner's request.

## 5. Stubs and their debts

No placeholder controls. Unknown metadata is a real reported state. No Preserve HDR switch or conversion option appears until the corresponding export contract exists. Stream-level probe data cannot certify all frame-level or dynamic metadata.

## 6. Modules touched

MediaProbe in ToolRunner.swift, MediaInspectorView.swift, a small internal presentation helper if useful, focused probe/presentation tests and planning evidence. EncodePlan may be referenced for explanatory wording, but its encoding arguments and acceptance policy do not change in this slice. No BatchController lifecycle changes.

## 7. Data subset

Optional stream fields: profile, color_primaries, color_space, color_range, existing color_transfer/pix_fmt, avg_frame_rate, r_frame_rate, sample_aspect_ratio, display_aspect_ratio, field_order and existing rotation metadata. Keep reported bit depth separate from pixel format; absent bits_per_raw_sample is not zero-bit video and no bit-depth claim is inferred by parsing arbitrary pixel-format strings. Rational values require finite components and a nonzero denominator. Do not infer constant or variable frame rate from two stream-level numbers.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S3-001 | Source tags appear with raw values and useful labels; absent/unrecognized fields remain visible and honest | JSON cases for Rec.709, PQ, HLG, absent fields, unrecognized transfer and partial metadata | video-inspection |
| S3-002 | Invalid ratios do not divide by zero or display NaN/infinity; average/base rate are distinctly labelled and do not imply a VFR verdict | Rational presentation tests, including 0/0 and malformed input | video-inspection |
| S3-003 | Real generated tagged SDR and 10-bit PQ/HLG fixtures decode through MediaProbe with the expected declared metadata | Existing tools generate local fixtures; actual ffprobe decode assertions | video-probe |
| S3-004 | Existing SDR/HDR plan acceptance and arguments remain unchanged; audio inspection, stream selection and reports still decode | Existing EncodePlan/audio regression plus missing-field fixtures | regression |
| S3-005 | Keyboard users can open/read/close the inspector; accessibility labels identify primaries, transfer, matrix, range and timing without implying certification | Native UI and accessibility-tree check; owner spoken review remains separate if unavailable | native-inspector |

Source tags are observations, not verified preservation. A fixture with HDR tags only proves tag handling, not correct HDR content or display.

## 9. Verification evidence required

Record tool versions and fixture recipes, test receipts, native UI observations and limitations. Use synthetic local fixtures only, never committed media or personal paths. One focused test group plus regression is proportionate; no new benchmark harness or observation service. No display-calibration claim.

## 10. Agent guardrails for this build

Stay within the read-only inspector boundary. No silent changes to encode options, source metadata, queue/session intent or native preset behavior. Unknown fields stay unknown. No new downloads, public media uploads, merges or releases. Any future color-preservation decision belongs to its own brief.

## 11. Slice definition of done

S3-001 through S3-005 have evidence, the native UI is usable and accurately labelled, and documentation distinguishes declared metadata from verified output. The owner can review the inspector without headphones. Broader HDR correctness and spoken acceptance are not inferred from test success.

## 12. What this unlocks

Separate briefs for explicit static HDR preservation and explicit HDR-to-SDR conversion, including bit depth, metadata, decoded-frame comparisons and hardware/display coverage. Filtered preview and frame stepping remain subsequent candidates.

Sources: [FFprobe documentation](https://ffmpeg.org/ffprobe.html) describes stream inspection and structured output. Field availability is checked against generated files using the installed ffprobe; absence is not a default.

Approved for build by: Daniel Boyd, 2026-09-29, following presentation of this bounded inspection proposal in the project conversation.
