# StaxRip Mac Slice 013: Verify resized output dimensions
Version: 0.1. Date: 2026-09-30. Status: Complete within recorded limits.

SLICE STATE
Milestone: M1 through M3 local/native geometry checks and hosted regression passed at 30b044b.
Blocked by: None external.
Evidence so far: PICTURE-GEOMETRY-EVIDENCE.md records generated exports, dropped-filter refusal, 122-test regression and native sizes. Restored-session access and main-thread publication blocking were observed and are tracked separately.
Last audit: 2026-09-30.

## 1. What the slice proves

A queue output cannot be published as successful if its encoded frame dimensions ignore the requested fit-to-size operation. Original-size outputs retain their exact upright cropped dimensions check. The verification claim is raster size, not pixel content or visual quality.

## 2. The walkthrough

Queue generated landscape and portrait videos using a resized preset. Check queue validates the geometry plan without writing media. Start queue creates outputs that fit the chosen raster box. Completed detail reports verified frame dimensions. A controlled encoder that drops resizing must fail before publication, with source/prior output and staging ownership preserved.

## 3. In scope, with build order

M1: Pure bounded frame-geometry contract after orientation/crop, using independently expressed fit invariants. M2: Supply that contract in EncodePlan and verify staged dimensions before publication, including a scoped result detail. M3: Pure rounding/bounds/refusal tests, actual 720p/1080p generated exports and intentionally dropped resize, ordinary regression, native portrait/landscape output checks and hosted validation.

## 4. Out of scope

New resize algorithms or presets, changed FFmpeg filters, square-pixel conversion, anamorphic display semantics, pixel-content/quality metrics, motion preview, frame-accurate seeking, audio, schema changes, merge and release.

## 5. Stubs and debts

Scale filter versions round to even sizes differently. Resized dimensions must be positive/even, remain within the configured raster box, touch one box edge, and differ from the ideal proportional raster fit by less than two pixels per axis (checked with exact bounded integer cross-products). This explicit rounding allowance does not certify sample aspect ratio or picture content. Existing orientation/SAR restrictions remain; unusual rotated resized SAR remains a separate policy limitation. No silent filter change.

## 6. Modules touched

New pure OutputGeometry contract, EncodePlan construction, BatchController pre-publication check/result summary, targeted tests and evidence. The shared PicturePlan filter expression is unchanged.

## 7. Data subset

Process-local positive width/height bounded by Int32.max, upright cropped raster geometry, optional 1280x720 or 1920x1080 bounding box. Overflow-safe finite arithmetic. Refuse a resized ideal edge below one pixel, which cannot round to a positive even edge under the supported scale behavior. No new persisted fields or migration.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S13-001 | Actual landscape/portrait/cropped resize outputs meet the raster contract | Generated real queue exports and output probe | geometry-export |
| S13-002 | Legitimate even rounding is accepted, absent/wrong/oversized geometry rejected | Pure boundary and variant fixtures | geometry-bounds |
| S13-003 | Encoder ignoring requested resize cannot publish; protected bytes and cleanup remain correct | Controlled dropped-filter export | geometry-refusal |
| S13-004 | Native result reports verified frame dimensions and output inspector agrees | Generated native queue walkthrough | geometry-ui |

## 9. Verification evidence required

Focused geometry tests, generated 720p/1080p exports, negative encoder case, regression including HDR/orientation, optimized native build, native result and hosted check. Exact tool versions and rounding limits recorded.

## 10. Guardrails

Verify before publication; never replace source or existing output. Preserve shared preview/queue filters. Do not label encoded raster dimensions as square-pixel display size. Do not weaken existing HDR, orientation, track, chapter or attachment verification.

## 11. Definition of done

S13-001 through S13-004 have local/native/hosted evidence and limits recorded. No general anamorphic or production-completion claim.

## 12. What this unlocks

A later explicit display-aspect and anamorphic policy can extend the same output contract after independent qualification.

Approved for build by: Owner autonomous non-audio delegation; activated under D-026 after Slice 012 closure.
