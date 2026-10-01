# StaxRip Mac Slice 026: Preserve SDR frame timing
Version: 0.1. Date: 2026-10-01. Status: Approved for build under D-040 / R-030.

SLICE STATE
Milestone: Planning complete; reproduce with actual EncodePlan next.
Blocked by: None.
Evidence so far: Generated discovery retained 24 frames but shifted irregular timestamps by up to 19 milliseconds with default encoder time base. This used traced equivalent arguments, not actual EncodePlan.
Last audit: 2026-10-01.

## 1. What the slice proves

Supported SDR exports request frame timestamp passthrough with the filter time base, avoiding unnecessary quantization to nominal frame rate. Generated decoded outputs establish scoped timing evidence. No runtime per-frame verification claim is added.

## 2. The walkthrough

Open a generated variable-rate source, choose ordinary software H.264 settings, queue and encode it. The queue finishes through its existing checks. Independent decoded timestamps preserve source frame count and timing within container quantization. Picture filtering and precise trimming retain their established semantics. Existing files remain protected.

## 3. In scope, with build order

M1: Actual EncodePlan regression reproduces irregular-timestamp drift before the fix. M2: Explicit SDR video passthrough and filter time base, leaving the audited HDR path unchanged. M3: generated VFR and fractional CFR integration across software codecs and MKV/MP4, crop/deinterlace and trim variants, local opt-in hardware checks, one native queue export, full regression/build and hosted gate.

## 4. Out of scope

New frame-rate conversion controls, persisted schema, full runtime source/output frame audits, HDR policy changes, copied-stream remux, negative or discontinuous timestamps, audio mastering/listening, long-film A/V sync, arbitrary codec/platform qualification, merge and release.

## 5. Stubs and debts

No stub in the changed argument path. Muxers can still alter timestamps. Existing output verification checks duration, geometry, tracks and scoped metadata; it does not promise frame-by-frame cadence verification. Unusual timestamps and representative films remain release debts.

## 6. Modules touched

EncodePlan, generated cadence integration tests and evidence documentation. BatchController, MediaProbe and ToolRunner are exercised through existing interfaces; no changes planned to those seams.

## 7. Data subset

No stored data change. Use decoded presentation timestamps from generated fixtures, bounded to short clips. Compare all expected frame counts and timestamps rather than nominal frame-rate tags. Allow at most one millisecond for MKV quantization and one output tick for MP4, with a small numeric comparison allowance.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S26-001 | Current actual plan fails irregular VFR timestamps; revised SDR plan preserves count/timing | Independent decoded input/output timestamps and negative control | cadence-vfr |
| S26-002 | H.264, HEVC, AV1 in MKV/MP4 preserve generated VFR and fractional CFR within declared quantization, including crop/deinterlace and trim | Real EncodePlan and batch integration | cadence-matrix |
| S26-003 | Local Apple hardware and one native queue export preserve the scoped generated timing and source bytes | Opt-in hardware checks, generated native walkthrough | cadence-native |
| S26-004 | Existing HDR, publication, source ownership and other regression remain intact | Full local/hosted suite, build and planning audit | cadence-regression |

## 9. Verification evidence required

One-second generated progressive SDR clips, including alternating short/long intervals and nominal-rate gaps, plus fractional 24000/1001 input. Before/after policy evidence must run the real plan. Check all decoded frames; record fractional trim rebasing separately. No broad benchmarking harness, time-limit changes or skipped failing assertions. Hardware evidence is local, not a hosted capability claim.

## 10. Guardrails

Apply video-specific options so audio time bases are unchanged. Keep static HDR10's accepted path and audits intact. Do not claim decoded cadence verification in the UI. Source and prior outputs remain unchanged. An encoder incompatibility must be investigated or explicitly scoped before acceptance, not hidden by fallback.

## 11. Definition of done

All four criteria have scoped evidence and the final hosted product/test head passes. Retain observed limits and source hashes. Audio remains parked.

## 12. What this unlocks

A better default for existing variable-rate media and firmer ground for later per-frame output audits and explicit frame-rate conversion.

Approved for build by: Owner overnight autonomous non-audio delegation, 2026-10-01; D-040 / R-030.
