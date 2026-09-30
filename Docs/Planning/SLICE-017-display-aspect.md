# StaxRip Mac Slice 017: Verify declared display proportions
Version: 0.1. Date: 2026-09-30. Status: Scoped acceptance passed.

SLICE STATE
Milestone: M3 local, native and hosted acceptance passed.
Blocked by: None within the slice; broader qualification remains separate.
Evidence so far: 157-test local regression, generated refusal/ownership checks, native known/unknown exports and hosted run 36790619197 passed. See DISPLAY-ASPECT-EVIDENCE.md and DISPLAY-ASPECT-RESEARCH.md.
Last audit: 2026-09-30.

## 1. What the slice proves

An advanced queue job whose source declares a valid pixel aspect ratio receives an output whose reported display proportions match the planned upright crop. An output with the right width and height but the wrong pixel shape cannot publish. If the source ratio is genuinely unavailable, the app says display proportions were not verified and preserves existing export capability without inventing square pixels.

## 2. The walkthrough

Open generated anamorphic SDR media and inspect its reported pixel shape. Apply a crop and fit within 1280x720. Check queue identifies the display verification contract. Encode and read the verified display-proportion result; independently inspect output raster and SAR. Run an unknown-SAR fixture and observe the explicit unavailable result. A generated wrong-SAR output with matching raster dimensions fails before publication.

## 3. In scope, with build order

M1: Bounded positive-rational parsing and exact reduced-fraction display comparison, with explicit unknown source values. M2: Add a display contract to EncodePlan using upright cropped dimensions, verify output before publication, and expose known/unavailable status in queue summaries and picture help. M3: Numeric boundaries, crop/scale/orientation reasoning, real MKV/MP4 software fixtures, malformed/missing/changed output ratios, ownership regression, native walkthrough and hosted acceptance.

## 4. Out of scope

New filters or aspect overrides, square-pixel conversion, retiming, frame-varying SAR detection, decoded pixel-quality equivalence, broader orientation/HDR support, native Quick Export, new audio work, saved-schema changes, signing, merge or release. This verifies reported stream display geometry, not every frame or every player.

## 5. Stubs and debts

Unknown source SAR is explicit unavailable evidence, not a 1:1 assumption. Existing filters and encoding choices remain unchanged. Frame-level changes, metadata conflicts beyond the selected stream report, obscure rational encodings and other platform/tool versions need broader qualification. Strict equality may refuse an encoder/container that approximates the declared ratio; do not add an unexplained floating tolerance.

## 6. Modules touched

A small display-aspect contract, EncodePlan, advanced BatchController verification, Picture settings explanation, focused tests and evidence. Reuse current media probe fields and OutputGeometry; do not replace raster validation.

## 7. Data subset

Reported SAR string, positive upright cropped dimensions and the expected reduced display fraction. Known SAR terms and raster values must fit positive Int32; products fit signed Int64. Reduce by GCD before equality comparison; do not cross-multiply two already multiplied fractions. Recognize only explicit missing/unknown forms as unavailable; reject other malformed input. No new persisted values or dependencies.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S17-001 | Known declared display proportions survive existing crop/resize plans | Exact numeric contract and actual MKV/MP4 extraction | display-aspect-preservation |
| S17-002 | Matching raster with wrong/missing/invalid output SAR cannot publish | Altered result fixtures and byte/ownership checks | display-aspect-refusal |
| S17-003 | Unknown source ratio remains explicit and is never inferred as square | Source/output fixtures, plan and final result assertions | display-aspect-unknown |
| S17-004 | Native user can inspect the scope and resulting display check | Generated native inspection/check/encode walkthrough | display-aspect-ui |

## 9. Verification evidence required

Positive/reducible/extreme rational values; missing and invalid fields; overflow boundaries; upright crop and proportional even scaling; software H.264/HEVC/AV1 in both containers; altered output with unchanged raster; retained source/prior outputs and owned staging; regression/build/native and hosted receipts. Hardware and real-film qualification remain narrower than this generated software evidence.

## 10. Guardrails

Keep existing codec, raster, duration, track, chapter, attachment and caption verification. No silent pixel-shape rewrite, new square-pixel assumption, changed settings or output replacement. Successful encoding alone cannot satisfy a known display contract.

## 11. Definition of done

S17-001 through S17-004 have scoped local/native/hosted evidence and explicit unknown/stream-only limitations. No whole-program or general anamorphic-film qualification claim.

## 12. What this unlocks

Later explicit aspect overrides, square-pixel conversion and broader VFR/anamorphic qualification can build on a stated, independently checked display contract.

Approved for build by: Owner autonomous non-audio delegation, activated under D-030 / R-020 after Slice 016 closure.

## M3 research finding, 2026-09-30

Full regression exposed near-square SAR loss in the existing MKV crop/fit case. Keep strict equality; validate the same successful crop through MP4 and add the actual MKV rounding refusal as separate coverage. DISPLAY-ASPECT-RESEARCH.md records the filter, encoder and container evidence. This is an intentional compatibility restriction with an actionable message, not a relaxation of S17-001 or removal of raster coverage.
