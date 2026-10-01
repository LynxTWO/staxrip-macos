# StaxRip Mac Slice 040: Preserve ten-bit SDR HEVC when copying video
Version: 0.1. Date: 2026-10-01. Status: Approved for build under D-078 / R-050.

SLICE STATE
Milestone: M1 complete; M2 bounded implementation may proceed.
Blocked by: None for the approved implementation.
Evidence so far: TEN-BIT-COPY-EVIDENCE.md records four generated complete-picture/packet comparisons, actual low-order ten-bit samples and retained incomplete-fixture refusal. No product support is claimed yet.
Last audit: 2026-10-01.

## 1. What the slice proves

A user can copy the original picture from a supported ten-bit SDR HEVC source into MKV or MP4 while changing supported caption/chapter choices. Today the app refuses that source before planning, even when no picture conversion is requested. Extend the existing verified copy contract, without adding a second export engine or changing SDR transcoding.

## 2. The walkthrough

Open a generated ten-bit HEVC source and inspect its declared Main 10 / BT.709 format. Choose Copy original, No audio, a plain generated SRT and a custom chapter list. Review the recipe and destination, start the queue and inspect the completed packet/picture/track result. An unsupported ten-bit/HDR source or picture conversion request stays an actionable refusal. Saved copy settings remain independent of stored encoding quality choices.

## 3. In scope, with build order

M1: A bounded generated feasibility probe of HEVC Main 10, yuv420p10le, explicitly declared BT.709 primaries/transfer/matrix and limited range. Confirm the actual source fields, complete ten-bit decoded pictures, packet/configuration identity and timestamp precision across MP4/Matroska sources and MKV/MP4 targets. Stop before implementation if this fails.

M2: Extend only the copy admission contract and shared planner's copy bypass of the transcode-only pixel restriction. Keep original upright/progressive/square-pixel/zero-start, timing, resource, source-stability and metadata/payload comparison contracts. Explain the two supported copy formats in visible and spoken native guidance.

M3: One small actual-queue matrix, admission/refusal checks, native walkthrough, ordinary local/hosted regression, optimized build and documentation.

## 4. Out of scope

HDR, HLG, PQ, dynamic metadata, ten-bit H.264, other subsampling/bit depths/color descriptions, new transcode modes, picture transformations, unusual-timestamp expansion, AV sync, audio processing/listening, broad player/hardware certification, new dependencies, schemas, merge and release. The existing eight-bit copy scope stays unchanged.

## 5. Stubs and debts

No product stub. Main 10 and color tags describe the declared format; they do not certify calibrated color or arbitrary hidden metadata. Higher bit depth alone is not evidence of HDR or SDR. Broader copy formats and visual/platform validation remain later work.

## 6. Modules touched

VideoCopyContract, EncodePlan and VideoRateOptions, plus existing copy tests and focused integration coverage. Reuse BatchController, video packet manifests, source checks, chapter/caption validation and exclusive publication without lifecycle changes. Do not alter the original mastering implementation or timing guards.

## 7. Data subset

No persisted field or version change. The existing Copy original/copy pair carries intent. This extension admits only HEVC Main 10 yuv420p10le with bt709 primaries, transfer and matrix and tv range, while retaining existing source metadata and packet comparison. Existing unknown-side-data refusal remains. Generated three-second silent fixtures, one plain SRT, flat custom chapters and private per-test journals stay in fresh owned folders. No private or licensed movie is needed.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S40-001 | Supported declared ten-bit SDR sources enter the copy path without a video encoder | M1 real fields plus typed contract/planner checks, no conversion arguments | ten-bit-copy-plan |
| S40-002 | Four source/target container combinations preserve complete pictures and time | Actual queue, 72 complete frames, genuine low-order ten-bit samples, matching raw ten-bit picture hashes and fixed per-frame 0.001001-second tolerance | ten-bit-copy-pictures |
| S40-003 | Added captions, custom chapters and original bytes remain protected | Full decoded SRT text/timing, chapter title/ranges, no audio, unchanged source/caption/prior-output bytes and settled owned staging | ten-bit-copy-tracks |
| S40-004 | Unsupported formats and altered output still refuse | Main/profile/pixel/color/HDR/unknown metadata counterexamples, transcode restriction retained, unchanged source/output metadata verifier | ten-bit-copy-refusal |
| S40-005 | A native user understands and executes the supported operation | Visible/spoken guidance inspection, real reviewed silent copy, independent output and safe prior-journal restoration | ten-bit-copy-native |
| S40-006 | Existing behavior stays qualified | Ordinary local/hosted generated regression, optimized build, unchanged earlier copy checks and selected planning audit | ten-bit-copy-regression |

## 9. Verification evidence required

M1 uses a fresh owned local folder and generated 160 by 96, 24 fps, three-second source. Bound the experiment to four container combinations and five minutes; no product patch until complete references agree. Integration keeps the existing two-minute small-case budget, source/caption bounds and all original copy/cancellation assertions. Use No audio, original size, no filters or trim. Decode references explicitly to yuv420p10le so eight-bit truncation cannot hide behind the reference conversion. Independently check at least one decoded frame contains meaningful low-order bits. Every output retains 72 decoded timestamps and the full decoded-picture digest. No tolerance accumulates. Positive cases pass through the real controller, packet verifier and publication. Existing cancellation and exclusive-output checks remain unchanged.

## 10. Guardrails

No generic high-bit-depth bypass: VideoCopyContract must authorize the source before EncodePlan skips an encoding-only restriction. Unsupported metadata/settings must not be silently cleared. Do not expand subtitle/audio/HDR contracts or weaken timing, payload, cancellation or resource limits. If the unresolved hosted mastering cancellation failure recurs, retain it and reopen qualification without another blind retry or diagnostic expansion.

## 11. Definition of done

All six gates have scoped evidence, native source/output handling is reviewed, prior owner state is restored, and the docs distinguish declared-format preservation from calibrated picture/player guarantees. No program-completion or listening acceptance claim follows.

## 12. What this unlocks

Supported ten-bit SDR material can use the existing verified track/container editing workflow without an unnecessary video re-encode. Broader HDR copy and transforms require separate later boundaries.

Approved for build by: Owner standing autonomous non-audio program-completion delegation, 2026-10-01; D-078 / R-050. Delegated to AI recommendation.
