# StaxRip Mac Slice 005: Filtered picture preview
Version: 0.1 Draft. Date: 2026-09-29. Status: Approved for build.

SLICE STATE
Milestone: M1, shared plan and extraction feasibility.
Blocked by: None.
Evidence so far: Existing implementation locators in section 6; proposed behavior is not implemented.
Last audit: 2026-09-29.

## 1. What the slice proves

A user can compare an original frame with the effect of the queue's crop, size and deinterlace settings before committing a full encode. Current playback is explicitly unfiltered. This adds visual feedback at Architecture section 10's picture-processing extension point.

Recommended scope is an on-demand still comparison. Alternatives are a short encoded motion preview, which also exposes compression but adds playback and sample-boundary qualification, or source-only frame stepping, which does not show the configured picture. Neither alternative is included here. Owner delegation informed the recommendation; the owner approved this brief on 2026-09-29.

Growth tally: shared picture plan, timestamp-matched frame pairs, bounded cancellable rendering, native comparison and stale-result handling. Continuous playback, timeline indexing and codec-quality comparison are deferred.

## 2. The walkthrough

1. Open a supported SDR source and configure picture settings in the workspace.
2. Choose Preview picture. Enter a source time within the configured trim interval; default to trim start. The action is explicit, not a background render on each keystroke.
3. Render a matched original/filtered pair. Show requested time, actual source presentation time, original dimensions and filtered dimensions. Do not call a rounded time an exact frame number.
4. Compare the two labelled images at fit size or 100 percent with scrolling. Keyboard and VoiceOver expose each image's role, timestamp, dimensions and applied operations.
5. Change settings or source: the previous result is marked out of date immediately. Refresh explicitly. Cancel or close during rendering without changing sources, queue entries or outputs.

## 3. In scope, with build order

| Milestone | Boundary |
| --- | --- |
| M1 | Extract a shared typed picture plan without changing existing queue arguments. Bounded feasibility check of matched-frame extraction with temporal deinterlacing before selection. Use generated fixtures to compare against a full reference render. Maximum three extraction approaches; stop and revise if identity cannot be proved. |
| M2 | Local preview service and controller: immutable configuration snapshot, source identity check, cancellation, stale-request rejection, owned temporary storage and explicit errors. |
| M3 | Native workspace comparison, fit/100 percent views, accessible controls, focused regression and UI walkthrough. |

Initial supported input: first video track, 8-bit 4:2:0 SDR, explicit BT.709 primaries/transfer/matrix and limited or full range, square pixels, no rotation, zero presentation start, dimensions up to 3840 by 2160. Reject missing/contradictory color or timing information with a reason specific to preview. Do not narrow the existing queue contract merely because preview has narrower coverage. Reject HDR preview explicitly. Support both progressive and interlaced sources when the requested deinterlace mode is supported.

Use existing crop, resize and BWDIF order and options. Trim defines the allowable source-time interval; it does not relabel source time as output time. Preserve temporal context through deinterlacing before selecting a frame. Original and filtered images must refer to the same source presentation time. Fail if no frame exists in the requested interval. No guessed average-rate frame numbering or fast-seek approximation may be labelled exact.

At most one render and one pair retained. Bound temporary image data to 128 MiB total and decoded image dimensions to the declared input/output cap. A render times out after 120 seconds and can be cancelled within five seconds. Decode from the beginning is acceptable for initial correctness, with visible progress and cost; fast seeking is allowed only if M1 proves equivalence. No full-movie frame index or cache. Record actual peak memory separately from these storage limits; no unmeasured movie-length performance promise.

## 4. Out of scope, on purpose

Motion playback, previous/next exact frame stepping, comparison of encoded quality/bitrate, HDR/tone mapping, anamorphic/rotated sources, arbitrary filters, subtitle burn-in, audio, queue-editor integration, new session fields, persistent preview cache, installation of tools, signing, merging and releases. D-018 records these exclusions. Later preview work connects through the same typed picture plan.

## 5. Stubs and their debts

No simulated filtered image. If preview cannot render, show the reason and retain ordinary source playback. Source playback remains labelled unfiltered. Preview demonstrates picture operations and does not guarantee final compression quality, calibrated display color or success of every export setting.

## 6. Modules touched and existing evidence

- EncodePlan.swift currently constructs BWDIF, crop and scale arguments directly in make. Extract only that typed picture logic for reuse and retain regression equivalence.
- PictureOptions.swift and WorkspaceView.swift own the current picture controls and explicitly describe unfiltered playback.
- WorkspaceModel.swift owns source/configuration replacement; these are invalidation boundaries.
- NativeVideoPreview.swift wraps AVPlayerView. Keep ordinary playback; use a separate native comparison view for stills.
- ToolRunner.swift and MediaProbe supply bounded process execution and source properties. Add only narrowly required metadata handling.
- New PicturePreview service/controller/view and focused tests. No new dependency or public API.

## 7. Data subset

Process-local PreviewRequest contains validated configuration, selected stream, source identity, requested time and generation ID. PreviewResult contains actual source timestamp, dimensions, filter summary, matching generation and owned image data. Results are never trusted from sessions. Source replacement, configuration change, close or newer request invalidates a generation; late completions cannot update the visible result. Check source identity before and after rendering; changes refuse the result. Reuse the established content fingerprint where practical and expose scan cost.

Temporary files live in a unique owned directory. Clean up on completion, cancellation and failure; report cleanup failures. Never reuse the configured destination directory as preview storage or remove another operation's data. No media or private paths in public fixtures or logs.

## 8. Acceptance criteria

| ID | Criterion | Verification | Gate |
| --- | --- | --- | --- |
| S5-001 | Preview and queue use identical picture operations in the same order | Regression argument comparison and generated asymmetric crop/resize fixtures, including no-op | picture-plan |
| S5-002 | Original and filtered frames share actual source time; temporal filtering agrees with full reference rendering | Numbered motion/interlaced fixtures, fractional frame rate, first/last frames, non-keyframe targets and missing-frame refusal; compare pre-display pixels | picture-frame |
| S5-003 | Display uses explicit supported SDR conversion and correct fit/100 percent geometry | Color/range test patterns, dimensions and native UI; calibrated fidelity is not claimed | picture-display |
| S5-004 | Cancel, timeout, malformed tool output, source change and late completion cannot show a current result | Focused real-process and controller fault tests; source and existing output hashes unchanged | picture-lifecycle |
| S5-005 | Only bounded image data and one active render remain | One generated 4K fixture, output-size limits, repeat refresh/close cleanup and a memory receipt; no benchmark campaign | picture-resource |
| S5-006 | Invalid crop, missing tools, unsupported color/rotation and stale results have clear recovery paths | Native walkthrough and accessibility-tree/keyboard checks; owner spoken acceptance tracked separately | picture-ui |

Preview does not validate audio/subtitle/container compatibility or authorize an encode. Truthful status and correction paths are part of S5-004/S5-006. Nothing is published by preview.

## 9. Verification evidence required

Focused tests, existing debug/release regression as appropriate, actual FFmpeg version, generated-fixture recipes, native walkthrough, cancellation/resource receipt and hosted result. Document first/last-frame behavior and the display conversion. Existing queue arguments must remain equivalent after extraction. Owner image/VoiceOver feedback remains distinct from machine checks. No general harness beyond the S5 fixtures.

## 10. Agent guardrails

Build only after this brief is approved. Stop if temporal identity or bounded output cannot be proved in M1. Do not silently substitute a source screenshot, change queue behavior, widen input support or install dependencies to make the demo pass. Preserve the parked audio pack and all existing export safeguards.

## 11. Definition of done

S5 checks have linked evidence; native core/error walkthroughs are complete; documentation explains the supported scope; owner walkthrough feedback is recorded separately. Unsupported formats and remaining visual/platform qualification stay visible.

## 12. What this unlocks

A later motion/compression sample preview and accurate frame navigation; shared validation for stronger output-dimension checks. Rotation/remux remains an independent candidate next slice.

Approved for build by: Owner, 2026-09-29. Approval followed presentation of PR 21 and delegated autonomous non-audio development.

## Reference

FFmpeg's [BWDIF documentation](https://ffmpeg.org/ffmpeg-filters.html#bwdif) describes motion-adaptive processing and send_frame output. Its [select documentation](https://ffmpeg.org/ffmpeg-filters.html#select_002c-aselect) exposes presentation timestamps and sequential filtered-frame indices. These support the proposed extraction investigation; they do not prove our preview implementation. Consulted 2026-09-29.

## Planning audit

D-018 is Confirmed and appears in the decision index. The owner approved the new build path. M1 schedules temporal-identity feasibility before dependent work. Existing code locators and companion documents were checked. Scope choices are explicitly proposals; no new unverified requirement is marked Confirmed. Mechanical audit on 2026-09-29 reports zero findings across eight recognized documents. This verifies document consistency only.
