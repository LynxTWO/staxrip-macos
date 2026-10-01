# StaxRip Mac Slice 032: Silent motion comparison
Version: 0.1. Date: 2026-10-01. Status: Approved for build under D-057 / R-040.

SLICE STATE
Milestone: Generated CFR/VFR timing, fragmented-file bounds and native decoder feasibility only.
Blocked by: None. Slice 031 accepted at a940665, plain hosted run 36840667407.
Evidence so far: motion-discovery receipts and motion-preview-next-notes.md retained locally.
Last audit: 2026-10-01.

## 1. What the slice proves

Users can inspect a short synchronized original/filtered motion comparison before encoding, with explicit proxy limits and safe cancellation/cleanup.

## 2. The walkthrough

Open generated SDR footage and change crop/deinterlacing. Open Picture comparison, choose Motion, enter a source time and render a silent three-second comparison. Play/pause/scrub one timeline with Original and Filtered labels. Change settings to invalidate the result, cancel a new render and close without leaving an active process or owned temporary files. Existing Still/frame stepping continues to work. Closing an idle comparison also releases its movie; quitting with a render or cleanup still active remains blocked until settlement.

## 3. In scope, with build order

M1: Establish rational frame-range/output-timestamp and proxy geometry contracts using the current PicturePlan, bounded generated positive/negative controls and a shared-clock composite. M2: Owned temporary render/result/player lifecycle, source identity and cancel/stale/close protection. M3: Native motion mode and truthful status/limits. M4: Native playback/cancel/close, local and hosted regression plus cleanup evidence.

## 4. Out of scope

Final compression comparisons, audio playback/listening, HDR, source admission wider than existing still preview, persistent preview cache, arbitrary clip export, approximate input seeking, remux and distribution.

## 5. Stubs and debts

No stub inside rendering, identity, playback ownership or cleanup. This is a downscaled H.264 viewing proxy, not final quality or calibrated color. Full-history filtering may be slow for late source times; timeout/cancellation must remain truthful. Still mode retains pixel inspection.

## 6. Modules touched

PicturePreview/PicturePlan reuse, a bounded motion planner/renderer/controller, PicturePreviewView and native player bridge, app operation ownership and scoped tests. No queue/session/audio schemas change.

## 7. Data subset

Existing validated SDR source/configuration. Source tagging must be complete; earlier timestamp-only feasibility clips with unknown transfer/primaries do not satisfy production admission. Fixed three-second requested source interval clipped to trim/source end, with at most 250 ms final-frame playback tail (3.25 seconds total); at most 600 selected frames, 64 MiB output and 120-second render window. Local owned temporary movie and typed source identity/rational timestamp sequence only. Candidate two 640 by 360 fitted panels, maximum composite 1280 by 360. A fragmented MP4 stdout sink must refuse each write before exceeding the byte cap, cancel its owned child, continue draining/discarding and await settlement. Disable B-frames in this viewing proxy because discovery found timestamp shifts with fragmented B-frame muxing. Preserve display proportions through explicit supported scaling; actual fit dimensions recorded. Fit uses display aspect including non-unit SAR introduced by PicturePlan scaling, then square proxy pixels with explicit even-pixel rounding.

## 8. Acceptance criteria

| ID | Criterion | Verified by | Gate |
| --- | --- | --- | --- |
| S32-001 | Supported CFR/VFR source frames match across both branches and composite output | Rational per-frame timing checks and counterexamples | motion-timing |
| S32-002 | Crop/deinterlace/orientation match full-history references; display shape is retained | Generated independent reference pixels/geometry | motion-picture |
| S32-003 | Unsupported or excessive input/result cannot produce an accepted preview | Bounds/range/size/count/source-change counterexamples | motion-admission |
| S32-004 | Cancellation, changed intent and close retain ownership until process/player settlement and clean only owned files | Controlled lifecycle and real cancellation checks | motion-lifecycle |
| S32-005 | Native playback/control labels, status and close work; still mode remains usable | Native light/dark keyboard walkthrough | motion-native |
| S32-006 | Existing protections remain | Full local/hosted tests, app build and audit | motion-regression |

## 9. Verification evidence required

Generated media only. Verify actual decoded timestamps, reference pictures, file limits and no audio. Demonstrate refusal for altered/extra/missing frames and stale source/intent. A passing child exit is insufficient. Record native playback movement/control response and cleanup after close, not merely a player screenshot. Native AVFoundation decode already matched 72 CFR / 48 VFR rational timestamps in discovery; this does not replace AVPlayer transport qualification. Verify native play advances time, pause holds it, seek moves it and close detaches the item before owned-file cleanup. Observe cleanup errors without starting a replacement operation. Capture recognized source-frame metadata incrementally with bounded line/frame storage; the existing 64 KiB retained stderr cannot hold the maximum two-branch showinfo trace. Any ToolRunner stderr observer must preserve default retention and drain/settlement behavior and receive its own partition/overflow/cancellation checks. Do not relax prior gates to make the new feature pass.

## 10. Guardrails

Never publish a clip into the user's destination. Do not begin a new render until the old operation and cleanup settle. Pausing/removing the player precedes owned-file removal. Keep warnings clear if cleanup fails, with no false success. Show the actually selected source interval and proxy nature. No auto sound, network or model download.

## 11. Definition of done

All six criteria have scoped evidence at the final tested head. No broader frame/color/media guarantee. Audio listening remains parked and no merge/release occurs.

## 12. What this unlocks

A native way to judge temporal picture settings before a long encode, while keeping exact still inspection available.

Approved for build by: Owner overnight autonomous non-audio delegation, 2026-10-01; D-057 / R-040.
