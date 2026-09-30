# Source orientation evidence
Date: 2026-09-30. Scope: Slice 007, D-020. Status: Done with local native, automated and hosted evidence.

## Research and bounded feasibility checks

FFmpeg documents display_rotation as counter-clockwise degrees and notes that autorotation is enabled by default. An explicit input display_rotation overrides file metadata. See [FFmpeg video options](https://ffmpeg.org/ffmpeg.html#Video-Options). The typed implementation will disable implicit autorotation, override the input display matrix to identity, and apply the validated pixel transform before crop. This makes the selected video stream's geometry explicit for both preview and queue.

On FFmpeg 9.0.2, a generated 160 by 96 asymmetric test pattern was encoded to H.264 with explicit SDR BT.709 metadata, then copied into four MP4 fixtures with 0/90/180/270-degree display rotations. Explicit no-op, counter-clockwise transpose, horizontal-plus-vertical flip, and clockwise transpose respectively produced the same first-frame YUV420 bytes as FFmpeg autorotation. Separately, an independent array permutation of every Y, U and V pixel matched all four explicit-filter frames byte for byte. The permutation did not invoke FFmpeg's orientation machinery.

Eight scratch exports, one for each angle/container pair (MP4 and MKV), used explicit transforms followed by asymmetric crop. Each output had the expected 152 by 92 or 88 by 156 dimensions and no display matrix. These are feasibility observations, not yet production-path tests. Source fixtures and JSON receipts stay in local scratch. No private media was used.

## Planned implementation acceptance

Require exact orthogonal fixed-point matrices with no reflection, scaling, translation or perspective. Verify reported angle and legacy tag agreement. Nonzero orientation supports progressive, square-pixel 8-bit SDR only, with deinterlacing Off. Queue and still preview will share this interpretation; output verification will reject a leftover transform before publication. HDR remains under its strict no-rotation contract.

Record focused unit/integration, native and hosted receipts here after they execute. Real-camera corpus, dynamic per-frame transforms, rotated HDR, arbitrary/mirrored orientation and other platforms remain unverified or unsupported.

## Implementation and local automated checks

SourceOrientation validates all nine fixed-point matrix coefficients and the reported angle. Reflected, translated, scaled, perspective, malformed and conflicting metadata are refused. Nonzero rotation requires progressive square-pixel 8-bit SDR with deinterlacing Off. The queue and still preview use the same explicit transform before crop. Queue geometry checks use upright dimensions, and staged rotated exports must have identity/no orientation and square pixels before publication. No session or preset schema changed.

Preview accepts portrait dimensions within the same 3840-by-2160 total-pixel budget and a 3840-pixel maximum per axis. Both sides are upright and keep matched source timestamps. The operations text names the applied angle. Picture settings explain upright crop edges and eligibility.

Two orientation tests include a matrix/source-contract table and a generated-media end-to-end loop. Four angles match independent Y/U/V array permutations byte for byte. Each preview matches a separately specified autorotation/crop/sRGB reference. Eight actual queue exports (four angles, MP4 and MKV) have expected dimensions, identity orientation, unchanged source fingerprints and decoded pixel mean-square error below 40 against the correctly oriented/cropped reference. A real reflected-matrix source is refused by both preview and queue; no destination or owned staging remains. A nonzero global video stream index is checked in plan arguments; the generated integration fixture has video stream zero.

The H.264 fixture initially lacked explicit primary/transfer metadata; the test fixture now annotates its known generated BT.709 content with h264_metadata. The strict source gate was retained. The next run exposed a real parser assumption: H.264 SEI lines can occur between the frame header and color record. Preview now selects exactly one color record within the current frame, before any next-frame header. Integration includes actual SEI, and parser regression covers intervening side data, duplicate colors and wrong-frame color. An initial regression used a mismatched synthetic address in its replacement string; correcting the test fixture made the intended rejection cases execute.

The final release regression reported 103 tests in 18 suites passed in 9.565 seconds, with 14 opt-in skips. This includes existing audio regression checks only; no listening or new mastering acceptance. Optimized app/native and hosted receipts follow after execution.

## Native walkthrough

The optimized ad-hoc app built in 12.13 seconds and was restarted. A generated 90-degree H.264 MP4 opened with native playback reporting 96 by 160. Picture settings exposed the upright-crop explanation. After setting all four crop edges to 2 pixels, the comparison showed an upright 96-by-160 original and 92-by-156 filtered image, both at source time 0.000000. The operations line named the 90-degree counter-clockwise orientation before crop. Labels, images, dimensions and explanatory text fit without clipping; accessibility exposed both image dimensions/times and orientation text.

A generated mirrored MP4 imported for source playback but its comparison request displayed the explicit unsupported-transform explanation and no images. Escape closed the sheet. Reopening a previously completed idle preview revealed an unrelated status defect: it said Cancelling even though no work was running. Cancel/close now distinguish idle state and clear stale state. Ten focused preview tests passed in 1.444 seconds (one opt-in skip), including the idle-close assertion. Final rebuilt native idle-reopen receipt follows.

Native agent inspection is not owner VoiceOver listening, calibrated display assessment or real-camera compatibility. Hosted check pending.

Final optimized ad-hoc build completed in 11.83 seconds. After restart, the portrait source rendered at 96 by 160 on both sides. Closing that completed comparison and reopening it showed Choose a source time, then render a comparison, with no stale image or false cancellation status. Native final follow-up passed. Draft PR 24 holds this slice; hosted result pending.

Hosted validation at a751166 passed in 9m22s: [run 36706425995](https://github.com/LynxTWO/staxrip-macos/actions/runs/36706425995). This includes the final idle-close repair. All local S7 gates have evidence within the documented source/platform scope.
