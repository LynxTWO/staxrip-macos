# StaxRip Mac Slice 007: Source orientation
Version: 0.1. Date: 2026-09-30. Status: In progress.

SLICE STATE
Milestone: M1 and M2 complete; M3 automated checks pass, native and hosted checks next.
Blocked by: None. Slice 006 closed with native and hosted evidence.
Evidence so far: Generated four-angle raw-frame comparison against FFmpeg autorotation; normalized MP4 has swapped dimensions and no rotation side data. ORIENTATION-EVIDENCE.md will hold implementation receipts.
Last audit: 2026-09-30.

## 1. What the slice proves

A user opens a progressive square-pixel SDR portrait clip whose display matrix declares a right-angle rotation, compares an upright source and filtered frame, crops relative to that upright image, and exports an upright encoded file. This closes the queue's current rotated-source refusal without a session migration or new dependency. D-020 records the delegated choice.

## 2. The walkthrough

1. Open a generated clip with a 90-degree display matrix.
2. Picture settings explain that crop edges follow the upright displayed image.
3. Render a comparison. Both sides are upright; the filtered side uses the requested crop. Actual source timestamps match.
4. Queue an encode. The plan reports the applied source orientation. Output pixels are upright and no further rotation is required in a player.
5. Open a mirrored or ambiguous source. Preview and queue refuse it with an actionable orientation explanation; no output is published.

## 3. In scope, with build order

| Milestone | Scope |
| --- | --- |
| M1 | Compare typed right-angle plans with FFmpeg's documented transform convention on generated asymmetric frames; prove output metadata normalization |
| M2 | Parse and validate full display matrices; share an orientation plan between queue and preview; crop validation uses upright dimensions; normalize input orientation metadata and explicitly rotate pixels |
| M3 | Native explanatory text and comparison; generated output/preview tests across all right angles and both containers; malformed/reflected matrix refusal; regression and hosted validation |

## 4. Out of scope

Arbitrary manual rotation, reflection, translated/scaled/perspective matrices, legacy nonzero rotate tags without a verified matrix, anamorphic rotated sources, interlaced rotated sources, rotated HDR, lossless remux, motion preview, frame stepping, new audio work, merge and distribution. Revisit in D-020 when representative real-camera fixtures establish those contracts.

## 5. Stubs and debts

No approximate matrix fallback. Unrecognized transformations fail rather than guessing an angle from one metadata field. Existing unrotated encoding behavior remains, including its current color/timing restrictions. This does not certify dynamic per-frame orientation changes or all phone formats.

## 6. Modules touched

MediaProbe side data; new SourceOrientation plan; EncodePlan and BatchController output verification; PicturePreview shared orientation; PictureOptions explanatory UI. Existing typed process execution, output publication and cancellation are reused. New generated-media orientation tests and existing regression suite.

## 7. Data subset

Read-only display matrix text and rotation angle from ffprobe. Recognize only exact fixed-point orthogonal matrices with no translation, perspective, reflection or scaling. Require matrix and reported angle agreement; reject duplicates and conflicting legacy tags. Nonzero supported orientation requires progressive, square-pixel 8-bit SDR and deinterlacing Off. No saved configuration, preset or session format change. Orientation is a property of the current source, never copied into a recipe.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S7-001 | 0/90/180/270-degree plans match displayed pixel orientation; malformed, reflected, conflicting and nonorthogonal matrices fail | Generated asymmetric frame and metadata tests, independent pixel permutation reference | orientation-plan |
| S7-002 | Crop follows upright coordinates and queue outputs expected dimensions with identity/no display matrix | Real encodes into MP4 and MKV, decoded image comparison and output metadata check | orientation-export |
| S7-003 | Original/filtered preview sides use the same orientation and timestamp; portrait bounds retain the existing pixel memory budget | Exact RGB reference comparison, crop bounds and image size tests | orientation-preview |
| S7-004 | User sees upright comparison, crop semantics and recoverable unsupported-transform message | Native generated-source walkthrough and accessibility inspection | orientation-ui |

## 9. Evidence required

Bounded synthetic fixtures only. Unit matrix rejection and independent pixel permutation reference, actual encoding and decoded comparison, focused and broad local checks, native walkthrough and hosted check. No benchmarking campaign or private camera corpus. Owner visual feedback and other OS/hardware coverage remain separate.

## 10. Guardrails

Preserve source bytes and prior outputs. No automatic tool downloads or silent transform fallback. Keep HDR's strict no-rotation audit. Preview retains one bounded pair and existing cancellation/time/source-identity guards. Clear normalization metadata before encoding and verify the staged result before publication. Do not widen unrelated pixel format or color support.

## 11. Definition of done

S7-001 through S7-004 have scoped local evidence; hosted status is recorded; architecture, requirements, decisions and release ledger are updated. Native agent inspection does not claim owner review, real-camera compatibility or production completion.

## 12. What this unlocks

Later anamorphic/geometry support and broader real-camera validation. Remux and exact-frame navigation remain independent candidates.

Approved for build by: Owner delegation of autonomous reasonable non-audio decisions on 2026-09-29, reaffirmed 2026-09-30. D-020 records scope selected under that delegation.
