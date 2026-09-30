# Filtered picture preview evidence
Date: 2026-09-29. Scope: Slice 005, D-018.

## Implementation

The workspace offers an explicit Picture comparison sheet. PicturePlan supplies the same BWDIF, crop and scale arguments to EncodePlan and PicturePreview. Ordinary AVPlayerView playback remains unfiltered. Preview supports the first video of an explicitly labelled, unrotated, square-pixel 8-bit SDR BT.709 source up to 3840 by 2160, with zero start and declared range/time base. Its narrower eligibility does not change queue eligibility.

Each side decodes from the beginning, applies the appropriate picture operations before selecting the first frame at or after the requested source time and before trim end, and emits one RGB frame. The original keeps interlacing; the filtered frame uses the configured BWDIF mode. Rational presentation timestamps must agree across original, filtered and display conversion. This is a still-picture comparison, not a compression-quality assessment or exact frame-navigation UI.

Selected-frame color declarations are checked against the source. FFmpeg colorspace converts BT.709 transfer to sRGB, then raw rgb24 is wrapped in an explicitly sRGB CGImage. Fit mode respects reported pixel aspect; 100 percent mode uses one image pixel per display pixel. Calibrated display fidelity remains untested. Operations are described in plain language.

No preview media is written to disk. This replaces the brief's provisional owned-directory design with bounded pipe buffers: each image is at most 24,883,200 bytes, and only one pair and one operation are retained. Oversized output cancels the decoder and fails. Missing, duplicate or inconsistent metadata and incomplete image bytes fail. Content fingerprints before and after bind the result to the source. Cancellation and timeout use ToolRunner's existing termination ladder; the app's quit guard includes active preview work. Generation IDs prevent late completions or progress from replacing a newer state. Source, settings or requested-time changes mark retained images out of date.

## M1 feasibility

Approach 1 passed; no alternative or fast-seek path was required. A generated FFV1 interlaced 160 by 96 fixture at 24000/1001 output rate was filtered with BWDIF and asymmetric crop. Selected pre-display YUV frames 0, 10 and 47 exactly matched corresponding slices of a complete reference render. Source times were 0, 0.417 and 1.960 seconds. This demonstrates the configured temporal context for these cases; arbitrary damaged or unsupported media is not certified.

## Focused verification

PicturePreviewTests covers shared queue arguments; independent full-render comparison at first/interior/last frames; no-op equality; resize; full-range input; trim gaps; missing/unsupported color, time base, rotation and crop; real cancellation and timeout; changed source; malformed/duplicate metadata and incomplete bytes; nonzero decoder exit and oversized stdout; controller invalidation and late completion; known black/white/midtone display levels; bounded 4K output.

An optimized isolated resource run retained 49,766,400 bytes for the 4K pair and reported test-helper peak resident memory of 105,037,824 bytes. No temporary media appeared beside the fixture. This measures one short generated source; it is not a whole-film throughput or total decoder-process memory guarantee.

## Native walkthrough

The generated interlaced MKV loaded through the fallback media probe while AVFoundation source playback correctly reported unavailable. Four-edge crop and All frames deinterlace were set in the native workspace. The comparison rendered requested 0.4 seconds as actual 0.417 seconds on both sides, with dimensions 160 by 96 and 156 by 92. Screenshot inspection showed both pictures, headings, dimensions and scope note without clipping. Pixel zoom toggled; changing time marked both images out of date; refreshing at 0.8 seconds produced a current pair at 0.834 seconds. An out-of-range request removed the result and showed a recoverable error. Accessibility values included image role, dimensions, timestamp and current/out-of-date status. Full owner spoken review remains separate.

## Limits and pending receipts

Final regression, final native label/quit-guard build and hosted validation are recorded below as they complete. Audio listening remains parked. No source media, private path, binary, merge or release is included in the PR.

## Final local receipt

Debug regression reported 93 tests in 16 suites passed in 203.542 seconds. Release regression reported 93 tests in 16 suites passed in 9.628 seconds. Both reported 14 opt-in skips; the separate resource run above enabled the 4K check. These are automated regressions, not new audio listening or mastering acceptance. The release run includes duplicate-metadata rejection, final image roles, plain-language operations and app-level preview ownership.

The final optimized ad-hoc app was rebuilt and restarted. A native session save/open restored the generated source and crop/deinterlace configuration. Rendering again reported matching 0.417-second frames, separate Original/Filtered image roles in accessibility, and the readable crop/deinterlace summary. The preview stores no files, so there is no staging cleanup debt from success or failure. The app-level quit guard is covered by source review and build; no claim is made of a forced-termination process test. Hosted validation remains pending at PR creation. Mechanical planning audit: zero findings across eight recognized documents.

## Hosted confirmation

PR 22 passed the hosted `test` check in 8 minutes 44 seconds at product commit 6be533e. [Run 36660799747](https://github.com/LynxTWO/staxrip-macos/actions/runs/36660799747/job/109714889825) records successful build and regression. Owner spoken/display qualification remains separate.
