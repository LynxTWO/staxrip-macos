# StaxRip Mac Slice 039: Licensed full-film video qualification
Version: 0.1. Date: 2026-10-01. Status: Approved for build under D-075 / R-049.

SLICE STATE
Milestone: Approved bounded qualification plan after Slice 038 acceptance.
Blocked by: None for implementation; actual film checks pending.
Evidence so far: LISTENING-MANIFEST.md supplies source acquisition/rights; read-only full decode confirms 21,312 frames at 24 fps, 1280 by 544, square pixels, yuv420p, zero start.
Last audit: 2026-10-01.

## 1. What the slice proves

The existing advanced queue can complete and independently validate a whole licensed 888-second SDR film through video copy, software H.264 and HEVC, retaining its embedded captions and adding two generated test tracks without changing the source.

## 2. The walkthrough

Open the licensed film with explicit source review. Select No audio, original size, Keep embedded tracks and two plainly labeled generated test caption files. Queue a new silent copy, review its real source/track/destination recipe and completed verification. Inspect the local independent full-film receipt. Do not play or assess the audio.

## 3. In scope, with build order

M1: An opt-in local test using the actual BatchController and the existing fixed licensed source identity. M2: Three sequential MKV exports (original-video copy, software H.264 CRF 20 Fast, HEVC CRF 22 Fast), No audio, all ten embedded SRTs and two generated tracks with early/middle/late cues. M3: Independent complete decoded frames/PTS/raster and subtitle references, source protection, native silent copy walkthrough and ordinary generated-only regression.

## 4. Out of scope

Audio processing/listening, A/V synchronization, subjective/objective picture quality metrics, calibrated HDR, feature-length/live-action representativeness, arbitrary metadata/player certification, new production behavior, merge and release. Hardware remains independently qualified by existing generated checks; it is not added to this matrix.

## 5. Stubs and debts

No product stub. This single 14.8-minute computer-animated film is one additional real-world case, not a representative corpus. Opt-in licensed media stays off hosted CI. Existing unusual-timestamp, broader color/codec/platform and filesystem limits remain open.

## 6. Modules touched

Tests and planning/evidence only. Reuse FFmpegTools, ToolRunner, MediaProbe, source fingerprints and BatchController. No production patch is approved without a separate evidence-backed decision. Never alter source, existing listening derivatives or prior owner recovery state.

## 7. Data subset

Sintel (2010), © Blender Foundation / sintel.org, CC BY 3.0, acquired from the official Blender distribution listed in LISTENING-MANIFEST.md. Fixed original SHA-256 f12c070e295b38cfc94ebd61ac3357c3bac82d1015985f1e8da93a4c6496c46d and 681,285,280 bytes. Retain credits and local attribution, label silent derivatives modified, imply no endorsement. Paths and media remain local; Git stores only code, source identity, licensing links and aggregate evidence. Local source/output parameters require an explicit opt-in environment, and every run creates a fresh owned output directory and private journal.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S39-001 | Only the reviewed licensed source runs and originals remain unchanged | Fixed digest/size, before/after source fingerprint, exclusive owned outputs, attribution | film-input |
| S39-002 | All three actual queue exports preserve the complete video timeline and raster | Exactly 21,312 decoded frames, increasing complete PTS, fixed per-frame one-millisecond precision, 1280 by 544 yuv420p; copied video also matches full decoded pixel hash | film-video |
| S39-003 | Complete retained/generated caption data survives each export | Independently decode all ten embedded and two added tracks; compare full UTF-8 cues/times and supported labels/language/order | film-captions |
| S39-004 | Native users can run and review the real silent copy | Explicit access/destination review, actual completed queue and independent output; prior journal restored safely | film-native |
| S39-005 | Ordinary behavior stays qualified | Existing optimized/native product provenance, ordinary full local/hosted generated-only regression and planning audit | film-regression |

## 9. Verification evidence required

Use one sequential test with a 15-minute full-case deadline and a fresh directory per run. Require at least 8 GiB available before starting. Bound source identity/size, three outputs, complete decoded frame count (21,312), each tool capture to the existing 4 MiB maximum, and subtitle decoding to 1 MiB per track. Refuse truncation and nonzero child exits. Check output sizes below 2 GiB after each export; this is a postcondition, not an in-flight filesystem quota. Compare every frame's PTS within 0.001001 seconds without accumulating tolerance. Require exact fixed geometry and pixel format on every frame, increasing timestamps, copied full decoded picture SHA-256, complete subtitle bytes and source identity before/after the matrix. Keep receipts per completed output with codec, frames, maximum timing difference, caption count, output bytes and whole-pipeline elapsed time. Preserve failure artifacts in the owned run directory after cancellation/settlement, without deleting unrelated paths. Cancellation joins actual batch/tool work before cleanup or failure propagation.

## 10. Guardrails

Do not weaken current guards or turn a refused source/output into a passed fixture. A metadata/timing/payload mismatch stops this slice for investigation. Do not upload media, use private owner films, touch concealed listening keys or use audio measurements as acceptance. No silent source edits, preset fallback, default scheduling changes or bypassed verification.

## 11. Definition of done

All five gates have scoped final-head receipts and explicit limitations. Ordinary CI does not acquire the licensed movie. A single full-film pass is not program completion, hearing acceptance or release readiness.

## 12. What this unlocks

Evidence that the short generated cases extend to an entire licensed film for the existing supported video/caption workflows, and a reproducible local reference for future video changes.

Approved for build by: Owner standing autonomous non-audio completion delegation, continued after D-074 and Slice 038 acceptance; D-075 / R-049.
