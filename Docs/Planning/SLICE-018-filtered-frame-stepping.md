# StaxRip Mac Slice 018: Exact filtered frame stepping
Version: 0.1. Date: 2026-09-30. Status: In progress.

SLICE STATE
Milestone: M3 local and native acceptance passed; hosted gate pending.
Blocked by: Hosted regression for this slice remains to run.
Evidence so far: 166-test release regression, 4K resource measurement and native VFR/trim/stale-state walkthrough passed. See FRAME-STEPPING-EVIDENCE.md.
Last audit: 2026-09-30.

## 1. What the slice proves

A user can move to the immediately preceding or following decoded source frame in the filtered comparison without guessing an interval from frame rate. Original and filtered pictures must correspond to the selected rational timestamp, or no new comparison is accepted.

## 2. The walkthrough

Open an explicitly tagged generated SDR VFR clip. Render a comparison. Step forward and backward across unequal timestamp gaps and see both images and actual source time change together. Reach first/last eligible trim frames and receive a boundary message. Change settings or source and observe stale-state protection before another step.

## 3. In scope, with build order

M1: Bounded streaming decoded-PTS neighbor discovery with strict order, anchor and trim checks; cancellation and actual process completion. M2: Bind a step to source fingerprint and current comparison, render through existing full-history filters and verify chosen timestamps. M3: Native previous/next buttons, state/accessibility, generated CFR/VFR/BWDIF pixel comparisons, boundary/failure/ownership checks and local/native/hosted acceptance.

## 4. Out of scope

Real-time motion playback, compressed-output previews, arbitrary seek acceleration, durable frame indexes, unknown/nonmonotonic timestamps, wider preview color/HDR/anamorphic support, audio, changed encode plans, persisted settings, merge, signing or release.

## 5. Stubs and debts

Long-source scans and source hashing may be expensive; retained memory and total operation time stay bounded. A timeout is explicit, not a guessed frame. Display precision does not replace rational timestamp identity. Existing narrow preview color/pixel-shape restrictions remain.

## 6. Modules touched

Preview timestamp scanner, PicturePreview request/result binding, PicturePreviewController/View, focused generated tests and evidence. Reuse ToolRunner process ownership and existing RGB display conversion.

## 7. Data subset

One prior PTS, current anchor, chosen neighbor and bounded partial text line; selected stream time base and source fingerprint. Positive rational terms up to existing HDRFraction bounds, PTS up to existing preview bound. Limit line size and scanned frame count. No whole-film frame array, temporary media or saved schema. At most the current and one replacement RGB pair coexist, bounded at 99,532,800 bytes before image/decoder overhead; measure resource usage separately.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S18-001 | Adjacent source frames are selected by decoded timestamps, including VFR gaps | Generated timestamp and independent pixel references | frame-step-neighbor |
| S18-002 | Original and filtered results match the chosen source frame | Rational stamps, BWDIF and full-render comparisons | frame-step-picture |
| S18-003 | Boundaries, invalid metadata, cancellation, mutation and stale callbacks cannot accept a wrong new frame | Parser/controller/integration cases and source hashes | frame-step-lifecycle |
| S18-004 | Native controls describe direction and actual frame time with explicit boundary/state feedback | Native generated walkthrough and accessibility tree | frame-step-ui |

## 9. Verification evidence required

CFR fractional cadence, VFR gaps, first/last trim bounds, independent full-history BWDIF RGB, equivalent time bases, malformed/duplicate/backward/missing/oversized timestamp output, process nonzero exit, cancellation/timeout settling, changed source, settings/time edits, no new media or source mutation, regression/build/native/hosted receipts.

## 10. Guardrails

Never use reciprocal average FPS as frame identity. Stop scanning only after sufficient ordered evidence; cancellation waits for process exit. A step cannot silently reuse an image from changed source/settings. Final original and filtered stamps must both match the selected neighbor. Retain existing memory limits and report unsupported media clearly.

## 11. Definition of done

S18-001 through S18-004 have scoped generated/local/native/hosted evidence. Motion preview, whole-film speed and broader media/platform validation remain separate.

## 12. What this unlocks

Precise visual crop/deinterlace inspection and later timeline/motion workflows with explicit decoded-frame identity.

Approved for build by: Owner autonomous non-audio delegation, activated under D-031 / R-021 after Slice 017 closure.
